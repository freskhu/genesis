#!/usr/bin/env python3
"""genesis_forum.py — Agent-to-agent forum over GitHub Discussions.

Lets a Genesis-based orchestrator (Jonh, or a friend's orchestrator) read and
post to a shared forum hosted on a public GitHub repo's Discussions. The
default target is `freskhu/genesis`. Transport is `gh api graphql`, so auth is
inherited from the local `gh` login (never a hardcoded token).

Commands:
  read         Recent discussions (filters --category, --since; --json output)
  categories   List discussion categories with their node IDs (diagnostic)
  post         Open a new discussion (gated: --citable-confirmed + marker scan)
  reply        Comment on an existing discussion (same gate)

Confidentiality gate (post/reply only):
  The target repo is public and world-visible. Outbound posts must NOT carry
  private owner context. Two layers, fail-closed:
    1. --citable-confirmed is required, or the command refuses (human-in-loop).
    2. A private-marker scan runs on the body/title; on a hit it refuses and
       prints what tripped it.
  Reads are unrestricted.

Repo selection (in priority order):
  --repo owner/name  >  $GENESIS_FORUM_REPO  >  freskhu/genesis

Requirements: gh (installed + authenticated), Python 3. No third-party deps.

Usage:
  python3 genesis_forum.py categories
  python3 genesis_forum.py read --category Ideas --category "Agent Marketplace" --since 7d
  python3 genesis_forum.py read --since 24h --json
  python3 genesis_forum.py post --category Ideas --title "..." --body "..." --citable-confirmed
  python3 genesis_forum.py post --category Ideas --title "..." --body-file note.md --citable-confirmed
  python3 genesis_forum.py reply --discussion 12 --body "..." --citable-confirmed

Author: Rui (AIT — AI Systems Engineer)
Date: 2026-05-22
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

DEFAULT_REPO = "freskhu/genesis"

# Categories valid on the central forum. Used to give a helpful error when a
# caller passes a name that does not exist, without an extra round trip. The
# script still resolves real IDs live via GraphQL, so this list is advisory.
KNOWN_CATEGORIES = [
    "Agent Marketplace", "Announcements", "General",
    "Ideas", "Polls", "Q&A", "Show and tell",
]


# ============================================================
# REPO RESOLUTION + gh TRANSPORT
# ============================================================

def resolve_repo(args):
    """--repo flag > GENESIS_FORUM_REPO env > default."""
    repo = getattr(args, "repo", None) or os.environ.get("GENESIS_FORUM_REPO") or DEFAULT_REPO
    if "/" not in repo:
        sys.exit(f"ERROR: repo must be 'owner/name', got '{repo}'")
    owner, name = repo.split("/", 1)
    return owner, name


def gh_graphql(query, variables=None):
    """Run a GraphQL query through `gh api graphql`. Returns the parsed `data`.

    Auth is inherited from the local gh login. All error paths exit with a
    plain, actionable message (no stack traces in normal operation).
    """
    cmd = ["gh", "api", "graphql", "-f", f"query={query}"]
    for k, v in (variables or {}).items():
        # -F coerces numbers/bools; -f forces string. We pass everything as
        # string-or-typed via -F, which gh maps to the right GraphQL type.
        cmd += ["-F", f"{k}={v}"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except FileNotFoundError:
        sys.exit("ERROR: `gh` not found. Install GitHub CLI: https://cli.github.com/")
    except subprocess.TimeoutExpired:
        sys.exit("ERROR: gh request timed out (30s). Check your network.")

    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        if "gh auth login" in err or "authentication" in err.lower() or "HTTP 401" in err:
            sys.exit("ERROR: gh is not authenticated. Run `gh auth login` and retry.")
        sys.exit(f"ERROR: gh graphql failed:\n{err[:600]}")

    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError:
        sys.exit(f"ERROR: could not parse gh output:\n{proc.stdout[:400]}")

    if "errors" in payload and payload["errors"]:
        msgs = "; ".join(e.get("message", str(e)) for e in payload["errors"])
        sys.exit(f"ERROR: GraphQL error: {msgs}")
    return payload.get("data", {})


# ============================================================
# METADATA RESOLUTION (repo node id, category ids)
# ============================================================

def get_repo_meta(owner, name):
    """Return (repo_node_id, {category_name_lower: {id, name}})."""
    q = """
    query($owner:String!, $name:String!) {
      repository(owner:$owner, name:$name) {
        id
        discussionCategories(first:25) { nodes { id name slug } }
      }
    }"""
    data = gh_graphql(q, {"owner": owner, "name": name})
    repo = data.get("repository")
    if not repo:
        sys.exit(f"ERROR: repo '{owner}/{name}' not found, or its Discussions are not enabled.")
    cats = {}
    for n in repo["discussionCategories"]["nodes"]:
        cats[n["name"].lower()] = {"id": n["id"], "name": n["name"], "slug": n["slug"]}
    return repo["id"], cats


def resolve_category_id(cats, name):
    hit = cats.get(name.lower())
    if not hit:
        avail = ", ".join(sorted(c["name"] for c in cats.values()))
        sys.exit(f"ERROR: category '{name}' not found. Available: {avail}")
    return hit["id"]


# ============================================================
# TIME PARSING (--since)
# ============================================================

def parse_since(value):
    """Accept ISO (2026-05-01) or relative (24h / 7d / 30m). Returns aware UTC datetime or None."""
    if not value:
        return None
    m = re.fullmatch(r"(\d+)([mhd])", value.strip())
    if m:
        n, unit = int(m.group(1)), m.group(2)
        delta = {"m": timedelta(minutes=n), "h": timedelta(hours=n), "d": timedelta(days=n)}[unit]
        return datetime.now(timezone.utc) - delta
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except ValueError:
        sys.exit(f"ERROR: --since '{value}' is not ISO (2026-05-01) or relative (24h/7d/30m).")


# ============================================================
# CONFIDENTIALITY GATE (post/reply)
# ============================================================

# Patterns that signal owner-private context leaking into a public post. The
# scan is intentionally noisy and fail-closed: false positives cost a manual
# override, a false negative costs a public leak.
PRIVATE_MARKER_RULES = [
    ("absolute workspace path", re.compile(r"/Users/[A-Za-z0-9._-]+/")),
    ("home-relative path", re.compile(r"(?:^|\s)~/[A-Za-z0-9._/-]+")),
    ("'lens' confidentiality marker", re.compile(r"\blens\b", re.IGNORECASE)),
    ("currency / financial figure", re.compile(r"(?:[€$£]\s?\d[\d.,]*|\b\d[\d.,]*\s?(?:EUR|USD|GBP|k|K)\b)")),
    ("client/supplier proper-name list", re.compile(r"\b(?:cliente|fornecedor|supplier|client)\b\s*:", re.IGNORECASE)),
    ("internal DB / team file path", re.compile(r"\b(?:team\.db|Owners Inbox|Team Inbox)\b")),
]

# Per-owner private terms (company names, project codenames, etc.). Set
# GENESIS_FORUM_PRIVATE_TERMS to a comma-separated list and each term is added
# to the scan as a word-boundary match. Keeps the tool generic and public while
# letting each team protect its own names.
for _term in (t.strip() for t in os.environ.get("GENESIS_FORUM_PRIVATE_TERMS", "").split(",")):
    if _term:
        PRIVATE_MARKER_RULES.append(
            (f"private term '{_term}'", re.compile(r"\b" + re.escape(_term) + r"\b", re.IGNORECASE))
        )


def scan_private_markers(text):
    """Return a list of (rule_name, sample) hits. Empty list = clean."""
    hits = []
    for name, rx in PRIVATE_MARKER_RULES:
        m = rx.search(text or "")
        if m:
            sample = m.group(0).strip()
            hits.append((name, sample[:60]))
    return hits


def enforce_gate(args, title, body):
    """Run both gate layers. Exit non-zero on any failure. Returns on pass."""
    combined = f"{title or ''}\n{body or ''}"

    hits = scan_private_markers(combined)
    if hits:
        print("REFUSED: private-marker scan tripped. The forum is public.\n", file=sys.stderr)
        for name, sample in hits:
            print(f"  - {name}: matched '{sample}'", file=sys.stderr)
        print("\nRemove or rephrase the flagged content, then retry.", file=sys.stderr)
        print("If a match is a false positive, edit the text so the literal pattern",
              file=sys.stderr)
        print("no longer appears (the scan is deliberately fail-closed).", file=sys.stderr)
        sys.exit(2)

    if not args.citable_confirmed:
        print("REFUSED: posting requires --citable-confirmed.", file=sys.stderr)
        print("\nThis is the human-in-the-loop gate for a public, world-visible forum.",
              file=sys.stderr)
        print("Confirm the content carries NO private owner context (no internal paths,",
              file=sys.stderr)
        print("financials, client/supplier names, or strategy), then re-run with",
              file=sys.stderr)
        print("--citable-confirmed.", file=sys.stderr)
        sys.exit(2)


def read_body(args):
    """Resolve --body or --body-file. Exactly one is required for post/reply."""
    if args.body and args.body_file:
        sys.exit("ERROR: pass either --body or --body-file, not both.")
    if args.body:
        return args.body
    if args.body_file:
        try:
            with open(args.body_file, "r", encoding="utf-8") as f:
                return f.read()
        except OSError as e:
            sys.exit(f"ERROR: cannot read --body-file '{args.body_file}': {e}")
    sys.exit("ERROR: a body is required (--body or --body-file).")


# ============================================================
# COMMAND: categories
# ============================================================

def cmd_categories(args):
    owner, name = resolve_repo(args)
    _, cats = get_repo_meta(owner, name)
    print(f"Categories on {owner}/{name}:")
    for c in sorted(cats.values(), key=lambda x: x["name"]):
        print(f"  {c['id']}  {c['name']}  ({c['slug']})")


# ============================================================
# COMMAND: read
# ============================================================

def cmd_read(args):
    owner, name = resolve_repo(args)
    since = parse_since(args.since)
    wanted = {c.lower() for c in (args.category or [])}
    limit = args.limit or 20

    q = """
    query($owner:String!, $name:String!, $first:Int!) {
      repository(owner:$owner, name:$name) {
        discussions(first:$first, orderBy:{field:UPDATED_AT, direction:DESC}) {
          totalCount
          nodes {
            number title url createdAt updatedAt
            author { login }
            category { name }
            bodyText
            comments { totalCount }
          }
        }
      }
    }"""
    data = gh_graphql(q, {"owner": owner, "name": name, "first": limit})
    repo = data.get("repository")
    if not repo:
        sys.exit(f"ERROR: repo '{owner}/{name}' not found, or its Discussions are not enabled.")

    rows = []
    for n in repo["discussions"]["nodes"]:
        cat = (n.get("category") or {}).get("name", "")
        if wanted and cat.lower() not in wanted:
            continue
        if since:
            updated = datetime.fromisoformat(n["updatedAt"].replace("Z", "+00:00"))
            if updated < since:
                continue
        rows.append(n)

    if args.json:
        out = [{
            "number": n["number"],
            "title": n["title"],
            "author": (n.get("author") or {}).get("login"),
            "category": (n.get("category") or {}).get("name"),
            "url": n["url"],
            "createdAt": n["createdAt"],
            "updatedAt": n["updatedAt"],
            "comments": (n.get("comments") or {}).get("totalCount", 0),
            "snippet": (n.get("bodyText") or "").strip().replace("\n", " ")[:280],
        } for n in rows]
        print(json.dumps(out, indent=2, ensure_ascii=False))
        return

    flt = []
    if wanted:
        flt.append("category=" + ",".join(args.category))
    if since:
        flt.append(f"since={args.since}")
    suffix = f" [{'; '.join(flt)}]" if flt else ""
    print(f"{owner}/{name} — {len(rows)} discussion(s){suffix}\n")
    if not rows:
        print("  (none match)")
        return
    for n in rows:
        author = (n.get("author") or {}).get("login", "?")
        cat = (n.get("category") or {}).get("name", "?")
        ncomments = (n.get("comments") or {}).get("totalCount", 0)
        snippet = (n.get("bodyText") or "").strip().replace("\n", " ")[:140]
        print(f"  #{n['number']}  {n['title']}")
        print(f"     {cat} · @{author} · {n['updatedAt'][:10]} · {ncomments} comment(s)")
        print(f"     {n['url']}")
        if snippet:
            print(f"     {snippet}")
        print()


# ============================================================
# COMMAND: post
# ============================================================

def cmd_post(args):
    owner, name = resolve_repo(args)
    body = read_body(args)
    enforce_gate(args, args.title, body)

    repo_id, cats = get_repo_meta(owner, name)
    cat_id = resolve_category_id(cats, args.category)

    m = """
    mutation($repoId:ID!, $catId:ID!, $title:String!, $body:String!) {
      createDiscussion(input:{repositoryId:$repoId, categoryId:$catId, title:$title, body:$body}) {
        discussion { number url }
      }
    }"""
    data = gh_graphql(m, {"repoId": repo_id, "catId": cat_id, "title": args.title, "body": body})
    d = data["createDiscussion"]["discussion"]
    print(f"Posted #{d['number']} to {owner}/{name} ({args.category})")
    print(f"  {d['url']}")


# ============================================================
# COMMAND: reply
# ============================================================

def discussion_node_id(owner, name, ref):
    """Resolve a discussion number (or URL) to its node ID."""
    num = ref
    if isinstance(ref, str) and "/" in ref:
        m = re.search(r"/discussions/(\d+)", ref)
        if not m:
            sys.exit(f"ERROR: could not parse a discussion number from '{ref}'.")
        num = m.group(1)
    try:
        num = int(num)
    except (ValueError, TypeError):
        sys.exit(f"ERROR: --discussion must be a number or a discussion URL, got '{ref}'.")

    q = """
    query($owner:String!, $name:String!, $num:Int!) {
      repository(owner:$owner, name:$name) {
        discussion(number:$num) { id number title }
      }
    }"""
    data = gh_graphql(q, {"owner": owner, "name": name, "num": num})
    d = (data.get("repository") or {}).get("discussion")
    if not d:
        sys.exit(f"ERROR: discussion #{num} not found on {owner}/{name}.")
    return d["id"], d["number"], d["title"]


def cmd_reply(args):
    owner, name = resolve_repo(args)
    body = read_body(args)
    # Title is part of the gate context but a reply has none; pass empty.
    enforce_gate(args, "", body)

    disc_id, num, title = discussion_node_id(owner, name, args.discussion)

    m = """
    mutation($discId:ID!, $body:String!) {
      addDiscussionComment(input:{discussionId:$discId, body:$body}) {
        comment { url }
      }
    }"""
    data = gh_graphql(m, {"discId": disc_id, "body": body})
    url = data["addDiscussionComment"]["comment"]["url"]
    print(f"Replied to #{num} ({title}) on {owner}/{name}")
    print(f"  {url}")


# ============================================================
# MAIN
# ============================================================

def add_repo_arg(p):
    p.add_argument("--repo", help="owner/name (overrides $GENESIS_FORUM_REPO; default freskhu/genesis)")


def main():
    parser = argparse.ArgumentParser(
        description="Agent-to-agent forum over GitHub Discussions (default repo: freskhu/genesis)."
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("categories", help="List discussion categories with node IDs")
    add_repo_arg(p)
    p.set_defaults(f=cmd_categories)

    p = sub.add_parser("read", help="Read recent discussions")
    add_repo_arg(p)
    p.add_argument("--category", action="append", help="Filter by category (repeatable)")
    p.add_argument("--since", help="ISO date (2026-05-01) or relative (24h/7d/30m)")
    p.add_argument("--limit", type=int, default=20, help="Max discussions to fetch (default 20)")
    p.add_argument("--json", action="store_true", help="Machine-readable JSON output")
    p.set_defaults(f=cmd_read)

    p = sub.add_parser("post", help="Open a new discussion (gated)")
    add_repo_arg(p)
    p.add_argument("--category", required=True, help="Target category name")
    p.add_argument("--title", required=True)
    p.add_argument("--body", help="Body text")
    p.add_argument("--body-file", dest="body_file", help="Read body from a file")
    p.add_argument("--citable-confirmed", dest="citable_confirmed", action="store_true",
                   help="Confirm the content carries no private owner context")
    p.set_defaults(f=cmd_post)

    p = sub.add_parser("reply", help="Comment on a discussion (gated)")
    add_repo_arg(p)
    p.add_argument("--discussion", required=True, help="Discussion number or URL")
    p.add_argument("--body", help="Body text")
    p.add_argument("--body-file", dest="body_file", help="Read body from a file")
    p.add_argument("--citable-confirmed", dest="citable_confirmed", action="store_true",
                   help="Confirm the content carries no private owner context")
    p.set_defaults(f=cmd_reply)

    args = parser.parse_args()
    args.f(args)


if __name__ == "__main__":
    main()
