#!/usr/bin/env python3
"""corrections.py -- correction families, the repeat-correction nudge, and its measurement.

Why it exists: a large share of the owner's high-precision corrections are the second or
later one in the same session. The first correction cannot be caught by a mechanism; the
repetition can. When the owner corrects the orchestrator again in the same session, the
hook injects a short reminder before the model answers.

Two uses:
  corrections.py hook        called by .claude/hooks/correction-nudge.sh (stdin: hook JSON)
  corrections.py measure     share of corrections that were the second or later in a session

The families below are English phrasings. They are the part to tune to the language your
owner actually writes in: keep them few and precise, because a false positive here is a
nudge on a normal message.

Writes only date, session id and family to the log (CORRECTIONS_LOG, default
~/.mempalace/hook_state/corrections.tsv, mode 600). Never the message text. The counter
is per exact session_id: an empty session id neither counts nor nudges, so one session
cannot contaminate another.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import unicodedata
from collections import Counter
from datetime import date
from pathlib import Path

LOG = Path(os.environ.get(
    "CORRECTIONS_LOG", str(Path.home() / ".mempalace" / "hook_state" / "corrections.tsv")))
MAX_TEXT = 600  # longer than this is a paste, not a correction

# High precision: only these nudge.
NUDGE_FAMILIES = {
    "made_up": re.compile(r"\b(you (just )?(made|make) (that|this|it) up|you(\'re| are) (making|inventing) (that|this|it|things)|you invented|stop inventing|that(\'s| is) invented)\b"),
    "already_said": re.compile(r"\b(i (already|just) (told|said|asked|explained)|i(\'ve| have) (already )?(told|said|explained) (you|this|that)|as i (already )?said)\b"),
    "how_many_times": re.compile(r"\bhow many times\b"),
    "had_access": re.compile(r"\b(you (always )?had access|you have (always )?had access|you do have access)\b"),
}


def normalise(text: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFKD", text.lower())
                   if not unicodedata.combining(c)).replace("’", "'")


def eligible(text: str) -> bool:
    """Excludes slash commands, system-injected messages and long pastes."""
    t = text.lstrip()
    return bool(t) and t[0] not in "/<" and len(text) <= MAX_TEXT


def nudge_family(text: str) -> str | None:
    if not eligible(text):
        return None
    n = normalise(text)
    for name, rx in NUDGE_FAMILIES.items():
        if rx.search(n):
            return name
    return None


def _read_log() -> list[tuple[str, str, str]]:
    if not LOG.exists():
        return []
    rows = []
    for line in LOG.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) == 3:
            rows.append((parts[0], parts[1], parts[2]))
    return rows


def _append(session: str, family: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(LOG, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    with os.fdopen(fd, "a", encoding="utf-8") as f:
        f.write(f"{date.today().isoformat()}\t{session}\t{family}\n")


def hook(stdin_txt: str) -> str:
    """Returns the nudge JSON, or an empty string."""
    d = json.loads(stdin_txt)
    session = str(d.get("session_id") or "").strip()
    if not session or "\t" in session or "\n" in session:
        return ""
    family = nudge_family(str(d.get("prompt") or ""))
    if family is None:
        return ""
    earlier = sum(1 for _, s, _f in _read_log() if s == session)
    _append(session, family)
    if earlier < 1:
        return ""
    return json.dumps({"hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": (
            f"Correction number {earlier + 1} in this session (family: {family}). Before "
            "answering: re-read your last claim; cite its source or say you do not have one; "
            "if an agent is running, pass the correction on in the owner's own words."
        ),
    }}, ensure_ascii=False)


def measure(since: str) -> dict:
    """Aggregates from the log since `since`. Numbers only."""
    seen: Counter = Counter()
    families: Counter = Counter()
    total = repeat = 0
    for day, session, family in _read_log():
        if day < since:
            continue
        total += 1
        families[family] += 1
        if seen[session] >= 1:
            repeat += 1
        seen[session] += 1
    pct = round(100 * repeat / total, 1) if total else None
    return {"since": since, "total": total, "second_or_later": repeat, "pct": pct,
            "sessions": len(seen), "families": dict(families)}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("action", choices=["hook", "measure"])
    ap.add_argument("--since", default="2000-01-01")
    a = ap.parse_args()
    if a.action == "hook":
        try:
            out = hook(sys.stdin.read())
            if out:
                print(out)
        except Exception:
            pass  # fail-open: a lost nudge costs less than an error on the owner's message
        return 0
    m = measure(a.since)
    print(f"corrections since {m['since']}: {m['total']} in {m['sessions']} sessions; "
          f"second or later in the same session: {m['second_or_later']} ({m['pct']}%)")
    print(f"families: {m['families']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
