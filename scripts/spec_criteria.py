#!/usr/bin/env python3
"""spec_criteria.py -- machine-readable acceptance criteria for specs in Team/_briefs/.

A spec's "## Acceptance criteria" section holds one `- [ ]` box per criterion. This
script reads the boxes into the `spec_criteria` table (migration 027) and moves each
criterion through its life cycle:

    fail --claim--> claimed --verify--> verified
      |                |  `--fail--> fail
      `--waive--> waived            (only with the owner's decision quoted in --note)

The author points at the proof (`claim --evidence`); someone else opens it and verifies.
The database triggers refuse a verifier who authored or claimed the criterion. The boxes
in the file are a derived view: `close` ticks them; ticking them by hand changes nothing.

Usage (global options go BEFORE the subcommand):
  spec_criteria.py [--db PATH] [--workspace PATH] ingest  --spec P [--author NAME]
  spec_criteria.py status  --spec P [--json]
  spec_criteria.py claim   --spec P --criterion N --by NAME --evidence "path:line | command and output"
  spec_criteria.py verify  --spec P --criterion N --by NAME
  spec_criteria.py fail    --spec P --criterion N --by NAME --note "why"
  spec_criteria.py waive   --spec P --criterion N --by NAME --note "owner decision, quoted"
  spec_criteria.py close   --spec P

Ingest rules: criteria are matched by the hash of their normalised text. A criterion
whose text changed is a new criterion; the old row goes to `superseded`. Numbered lists
do not count: only `- [ ]` / `- [x]` boxes, with indented continuation lines appended.

Redacted mode: for specs whose path matches SPEC_CRITERIA_REDACT_GLOB (default
`Team/_briefs/*health*`), the stored text is a pointer to the line in the file, never the
criterion itself. The database is readable by every agent; a sensitive spec's criteria
stay in the file (.claude/rules/health-data-boundary.md).

Evidence is a POINTER (path:line, command with its exit code, a short quote), never the
proof itself, and never a secret value, health data or company financial figures.

Exit codes:
  0 done   2 invalid input   3 spec not found   4 infrastructure (DB, table)
  5 refused (transition, verifier, open criteria on close)   6 spec has no criteria
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import sqlite3
import sys

EXIT_OK, EXIT_INPUT, EXIT_NO_SPEC, EXIT_INFRA, EXIT_REFUSED, EXIT_NO_CRITERIA = 0, 2, 3, 4, 5, 6

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_WORKSPACE = os.path.dirname(SCRIPT_DIR)
SECTION_RE = re.compile(r"^##\s+acceptance criteria\b", re.IGNORECASE)
BOX_RE = re.compile(r"^\s*[-*]\s+\[( |x|X)\]\s+(.*\S)\s*$")
REDACT_GLOB = os.environ.get("SPEC_CRITERIA_REDACT_GLOB", "Team/_briefs/*health*")


class Refused(Exception):
    pass


def die(msg: str, code: int) -> None:
    print(f"spec_criteria: {msg}", file=sys.stderr)
    sys.exit(code)


def now(conn) -> str:
    return conn.execute("SELECT strftime('%Y-%m-%dT%H:%M:%SZ','now')").fetchone()[0]


def connect(db_path: str) -> sqlite3.Connection:
    if not os.path.exists(db_path):
        die(f"database not found: {db_path}", EXIT_INFRA)
    try:
        conn = sqlite3.connect(db_path, timeout=5)
        for p in ("PRAGMA foreign_keys = ON", "PRAGMA journal_mode = WAL",
                  "PRAGMA busy_timeout = 5000", "PRAGMA synchronous = NORMAL"):
            conn.execute(p)
        if not conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' "
                            "AND name='spec_criteria'").fetchone():
            die("table spec_criteria missing: apply Database/migrations/027_spec_criteria.sql",
                EXIT_INFRA)
    except sqlite3.Error as e:
        die(f"database error: {e}", EXIT_INFRA)
    return conn


def resolve_spec(raw: str, workspace: str) -> tuple[str, str]:
    """Returns (relative path with forward slashes, absolute path)."""
    raw = raw.strip().lstrip("@")
    absolute = raw if os.path.isabs(raw) else os.path.join(workspace, raw)
    absolute = os.path.normpath(absolute)
    rel = os.path.relpath(absolute, workspace).replace(os.sep, "/")
    if not fnmatch.fnmatchcase(rel, "Team/_briefs/*.md") or ".." in rel or "\n" in rel:
        die(f"not a spec path under Team/_briefs/: {raw}", EXIT_INPUT)
    if not os.path.isfile(absolute):
        die(f"spec not found: {rel}", EXIT_NO_SPEC)
    return rel, absolute


def normalise(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def parse_spec(lines: list[str]) -> list[tuple[int, str, bool]]:
    """(line number, criterion text, ticked) for each box of the acceptance section."""
    out: list[list] = []
    in_section = False
    for n, line in enumerate(lines, start=1):
        if line.startswith("#"):
            if SECTION_RE.match(line):
                in_section = True
                continue
            if in_section and re.match(r"^#{1,2}\s", line):
                break
            continue
        if not in_section:
            continue
        m = BOX_RE.match(line)
        if m:
            out.append([n, m.group(2), m.group(1).lower() == "x"])
        elif out and line.strip() and line[:1].isspace() and not line.lstrip().startswith("<!--"):
            out[-1][1] += " " + line.strip()     # continuation line
    return [(n, normalise(t), ticked) for n, t, ticked in out if normalise(t)]


def actor_id(conn, name: str):
    row = conn.execute("SELECT id FROM team_members WHERE lower(name) = lower(?)",
                       (name,)).fetchone()
    return row[0] if row else None


def log_activity(conn, name: str, action: str, spec: str, summary: str, meta: dict,
                 entity_id=None) -> None:
    """activity_history needs a team_members row; without one the change is not logged."""
    aid = actor_id(conn, name)
    if aid is None:
        return
    conn.execute(
        "INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, metadata) "
        "VALUES (?, ?, 'spec_criterion', ?, ?, ?)",
        (aid, action, entity_id, summary[:500], json.dumps({"spec": spec, **meta})))


def live_rows(conn, spec: str):
    return conn.execute(
        "SELECT id, ordinal, status, text, author, claimed_by, evidence, verified_by, note "
        "FROM spec_criteria WHERE spec_path = ? AND status <> 'superseded' ORDER BY ordinal",
        (spec,)).fetchall()


def pick(conn, spec: str, ordinal: int):
    row = conn.execute(
        "SELECT id, status, author, claimed_by FROM spec_criteria "
        "WHERE spec_path = ? AND ordinal = ? AND status <> 'superseded'",
        (spec, ordinal)).fetchone()
    if not row:
        die(f"no criterion {ordinal} in {spec} (run ingest first?)", EXIT_INPUT)
    return row


def checked_text(value: str | None, field: str, limit: int) -> str:
    if value is None or not value.strip():
        die(f"--{field} is required and cannot be empty", EXIT_INPUT)
    if len(value) > limit:
        die(f"--{field} longer than {limit} characters", EXIT_INPUT)
    return value.strip()


# ------------------------------------------------------------------ commands

def cmd_ingest(conn, a, ws) -> int:
    spec, absolute = resolve_spec(a.spec, ws)
    with open(absolute, encoding="utf-8") as f:
        crit = parse_spec(f.read().splitlines())
    if not crit:
        die(f"{spec} has no `- [ ]` boxes under '## Acceptance criteria'", EXIT_NO_CRITERIA)
    redact = fnmatch.fnmatchcase(spec, REDACT_GLOB)
    seen, added = set(), 0
    ts = now(conn)
    with conn:
        for ordinal, (line, text, _ticked) in enumerate(crit, start=1):
            h = hashlib.sha256(text.encode("utf-8")).hexdigest()
            seen.add(h)
            stored = f"[criterion in file, line {line}]" if redact else text
            row = conn.execute("SELECT id, author FROM spec_criteria WHERE spec_path=? AND text_hash=?",
                               (spec, h)).fetchone()
            if row:
                conn.execute("UPDATE spec_criteria SET ordinal=?, source_line=?, updated_at=? WHERE id=?",
                             (ordinal, line, ts, row[0]))
                if a.author and row[1] is None:
                    conn.execute("UPDATE spec_criteria SET author=? WHERE id=?", (a.author, row[0]))
            else:
                # A superseded row may hold this ordinal; ordinals only need to be unique
                # among live rows, which the query in pick() enforces.
                conn.execute(
                    "INSERT INTO spec_criteria (spec_path, ordinal, text, text_hash, redacted, "
                    "source_line, author) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (spec, ordinal, stored, h, 1 if redact else 0, line, a.author))
                added += 1
        gone = [r[0] for r in conn.execute(
            "SELECT id, text_hash FROM spec_criteria WHERE spec_path=? AND status<>'superseded'",
            (spec,)) if r[1] not in seen]
        for rid in gone:
            conn.execute("UPDATE spec_criteria SET status='superseded', updated_at=? WHERE id=?",
                         (ts, rid))
    print(f"{spec}: {len(crit)} criteria ({added} new, {len(gone)} superseded)")
    return EXIT_OK


def cmd_status(conn, a, ws) -> int:
    spec, _ = resolve_spec(a.spec, ws)
    rows = live_rows(conn, spec)
    counts: dict[str, int] = {}
    for r in rows:
        counts[r[2]] = counts.get(r[2], 0) + 1
    if a.json:
        print(json.dumps({"spec": spec, "counts": counts, "criteria": [
            {"n": r[1], "status": r[2], "text": r[3], "author": r[4], "claimed_by": r[5],
             "evidence": r[6], "verified_by": r[7], "note": r[8]} for r in rows]},
            ensure_ascii=False, indent=2))
        return EXIT_OK
    print(f"{spec}: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    for r in rows:
        text = r[3] if len(r[3]) <= 90 else r[3][:87] + "..."
        print(f"  {r[1]:>3}  {r[2]:<9} {text}")
        if r[6]:
            print(f"       evidence: {r[6]}")
        if r[8]:
            print(f"       note: {r[8]}")
    return EXIT_OK


def update(conn, rid: int, sets: str, params: tuple) -> None:
    try:
        with conn:
            conn.execute(f"UPDATE spec_criteria SET {sets}, updated_at = ? WHERE id = ?",
                         params + (now(conn), rid))
    except sqlite3.IntegrityError as e:
        raise Refused(str(e)) from e


def cmd_claim(conn, a, ws) -> int:
    spec, _ = resolve_spec(a.spec, ws)
    ev = checked_text(a.evidence, "evidence", 1000)
    rid, status, author, _ = pick(conn, spec, a.criterion)
    if status not in ("fail", "claimed"):
        raise Refused(f"criterion {a.criterion} is {status}; only fail or claimed can be claimed")
    update(conn, rid, "status='claimed', claimed_by=?, claimed_at=?, evidence=?, author=COALESCE(author, ?)",
           (a.by, now(conn), ev, a.by))
    with conn:
        log_activity(conn, a.by, "spec_criterion_claimed", spec,
                     f"claimed criterion {a.criterion} of {spec}", {"criterion": a.criterion}, rid)
    print(f"{spec} #{a.criterion}: claimed by {a.by}")
    return EXIT_OK


def cmd_verify(conn, a, ws) -> int:
    spec, _ = resolve_spec(a.spec, ws)
    rid, status, author, claimed_by = pick(conn, spec, a.criterion)
    if status != "claimed":
        raise Refused(f"criterion {a.criterion} is {status}; only claimed can be verified")
    update(conn, rid, "status='verified', verified_by=?, verified_at=?", (a.by, now(conn)))
    with conn:
        log_activity(conn, a.by, "spec_criterion_verified", spec,
                     f"verified criterion {a.criterion} of {spec}", {"criterion": a.criterion}, rid)
    print(f"{spec} #{a.criterion}: verified by {a.by}")
    return EXIT_OK


def cmd_fail(conn, a, ws) -> int:
    spec, _ = resolve_spec(a.spec, ws)
    note = checked_text(a.note, "note", 2000)
    rid, status, _, _ = pick(conn, spec, a.criterion)
    update(conn, rid, "status='fail', note=?, verified_by=NULL, verified_at=NULL", (note,))
    with conn:
        log_activity(conn, a.by, "spec_criterion_failed", spec,
                     f"failed criterion {a.criterion} of {spec}", {"criterion": a.criterion,
                                                                     "was": status}, rid)
    print(f"{spec} #{a.criterion}: fail ({a.by})")
    return EXIT_OK


def cmd_waive(conn, a, ws) -> int:
    spec, _ = resolve_spec(a.spec, ws)
    note = checked_text(a.note, "note", 2000)
    rid, status, _, _ = pick(conn, spec, a.criterion)
    update(conn, rid, "status='waived', note=?", (note,))
    with conn:
        log_activity(conn, a.by, "spec_criterion_waived", spec,
                     f"waived criterion {a.criterion} of {spec}", {"criterion": a.criterion}, rid)
    print(f"{spec} #{a.criterion}: waived ({a.by})")
    return EXIT_OK


def cmd_close(conn, a, ws) -> int:
    spec, absolute = resolve_spec(a.spec, ws)
    rows = conn.execute("SELECT ordinal, status, text_hash FROM spec_criteria "
                        "WHERE spec_path=? AND status<>'superseded' ORDER BY ordinal",
                        (spec,)).fetchall()
    if not rows:
        die(f"{spec} has no ingested criteria", EXIT_NO_CRITERIA)
    open_ = [f"#{o} {s}" for o, s, _ in rows if s not in ("verified", "waived")]
    if open_:
        raise Refused("open criteria: " + ", ".join(open_))
    done = {h for _, s, h in rows}
    with open(absolute, encoding="utf-8") as f:
        lines = f.read().splitlines(keepends=True)
    parsed = parse_spec([l.rstrip("\n") for l in lines])
    for line_no, text, ticked in parsed:
        if not ticked and hashlib.sha256(text.encode("utf-8")).hexdigest() in done:
            lines[line_no - 1] = re.sub(r"\[ \]", "[x]", lines[line_no - 1], count=1)
    with open(absolute, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print(f"{spec}: closed, {len(rows)} criteria ticked in the file")
    return EXIT_OK


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--db", default=None, help="default: <workspace>/Database/team.db")
    p.add_argument("--workspace", default=DEFAULT_WORKSPACE)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("ingest", help="read the spec's boxes into the table")
    s.add_argument("--spec", required=True); s.add_argument("--author")
    s = sub.add_parser("status", help="state of a spec's criteria")
    s.add_argument("--spec", required=True); s.add_argument("--json", action="store_true")
    for name, extra in (("claim", "evidence"), ("verify", None), ("fail", "note"), ("waive", "note")):
        s = sub.add_parser(name)
        s.add_argument("--spec", required=True)
        s.add_argument("--criterion", type=int, required=True)
        s.add_argument("--by", required=True)
        if extra:
            s.add_argument(f"--{extra}", required=True)
    s = sub.add_parser("close", help="tick the boxes in the file once all are verified or waived")
    s.add_argument("--spec", required=True)
    return p


def main(argv=None) -> int:
    a = build_parser().parse_args(argv)
    ws = os.path.abspath(a.workspace)
    conn = connect(a.db or os.path.join(ws, "Database", "team.db"))
    handler = {"ingest": cmd_ingest, "status": cmd_status, "claim": cmd_claim,
               "verify": cmd_verify, "fail": cmd_fail, "waive": cmd_waive,
               "close": cmd_close}[a.cmd]
    try:
        return handler(conn, a, ws)
    except Refused as e:
        print(f"spec_criteria: refused: {e}", file=sys.stderr)
        return EXIT_REFUSED
    except sqlite3.Error as e:
        print(f"spec_criteria: database error: {e}", file=sys.stderr)
        return EXIT_INFRA


if __name__ == "__main__":
    sys.exit(main())
