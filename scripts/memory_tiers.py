#!/usr/bin/env python3
"""
memory_tiers.py — Auto-promote/demote MemPalace drawers between hot/warm/cold tiers.

Tier logic (inspired by Enterprise blueprint):
  - HOT:  Structurally hot rooms/halls, the owner wing, manually pinned
  - WARM: Default tier. Actively accessed content; recent or reference-class.
  - COLD: Not accessed/reclassified in >30 days, outside hot/warm-class rooms.

The tier is stored as a top-level column in `drawers.tier` in team.db
(Database/team.db). Auxiliary timestamps (`tier_updated_at`, `tier_previous`,
`hall_reclassified_at`) live inside the JSON `drawers.metadata` blob and are
read/written via SQLite's json1 functions.

Backend: SQLite (Database/team.db). This script used to read a legacy
ChromaDB store at ~/.mempalace/palace — that store became orphaned once the
palace moved to sqlite-vec inside team.db, so it was re-pointed. If you ever
split the vector store back out, this is the file that has to follow it.

Usage:
  python3 memory_tiers.py                  # DRY RUN — show what would change
  python3 memory_tiers.py --execute        # LIVE — update team.db
  python3 memory_tiers.py --report         # Just show current tier distribution
  python3 memory_tiers.py --wing work      # Filter to a specific wing

Author: the orchestrator (AIT Orchestrator) — re-pointed to team.db
"""

import argparse
import json
import os
import sqlite3
import sys
from collections import defaultdict
from datetime import datetime

# team.db lives at <repo_root>/Database/team.db.
# This script is at <repo_root>/scripts/memory_tiers.py.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
DB_PATH = os.path.join(REPO_ROOT, "Database", "team.db")
BATCH_SIZE = 200

# Tier thresholds
COLD_DAYS = 30  # days since filed (or reclassified) with no activity → cold candidate
HOT_ROOMS = {
    # Rooms that are structurally hot (always loaded)
    "identity", "preferences", "protocols", "configuration",
}
HOT_HALLS = {
    # Halls that tend to be hot
    "hall_preferences", "hall_diary",
}
# Wing holding the owner's own profile — always hot. Rename to match your setup.
OWNER_WING = "owner"
WARM_ROOMS = {
    # Old content in these rooms stays warm (reference-class material)
    "reference", "architecture", "cases", "code",
}


def connect(db_path: str) -> sqlite3.Connection:
    """Open team.db with the standard PRAGMAs."""
    if not os.path.exists(db_path):
        print(f"ERROR: team.db not found at {db_path}", file=sys.stderr)
        sys.exit(2)
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON;")
    conn.execute("PRAGMA journal_mode = WAL;")
    conn.execute("PRAGMA busy_timeout = 5000;")
    conn.execute("PRAGMA synchronous = NORMAL;")
    conn.row_factory = sqlite3.Row
    return conn


def parse_metadata(raw: str) -> dict:
    """Safely parse the JSON metadata blob."""
    if not raw:
        return {}
    try:
        meta = json.loads(raw)
        return meta if isinstance(meta, dict) else {}
    except (json.JSONDecodeError, TypeError):
        return {}


def get_tier(row: sqlite3.Row, meta: dict, now: datetime) -> str:
    """Determine the tier for a drawer based on row + metadata + age."""
    room = row["room"] or ""
    hall = row["hall"] or ""
    wing = row["wing"] or ""

    # Structurally hot: identity, preferences, protocols, config rooms
    if room in HOT_ROOMS:
        return "hot"

    # Structurally hot: preference and diary halls
    if hall in HOT_HALLS:
        return "hot"

    # The owner wing is always hot (owner profile)
    if wing == OWNER_WING:
        return "hot"

    # Recently reclassified = warm
    reclassified_at = meta.get("hall_reclassified_at", "")
    if reclassified_at:
        try:
            rc_date = datetime.fromisoformat(reclassified_at)
            if (now - rc_date).days < COLD_DAYS:
                return "warm"
        except (ValueError, TypeError):
            pass

    # NOTE: tier_updated_at is deliberately NOT used as a recency signal.
    # It is demotion/promotion bookkeeping written by this script's own
    # --execute pass, not a real activity touch. Treating it as activity
    # made every executed drawer look "recently active" and bounced cold
    # drawers back to warm on the next run (non-idempotent). Recency now
    # relies only on genuine signals: hall_reclassified_at and filed_at.

    # Check filed_at age
    filed_at_str = row["filed_at"] or meta.get("filed_at", "")
    try:
        # team.db stores filed_at as "YYYY-MM-DD HH:MM:SS" by default;
        # also tolerate ISO 8601 with T.
        normalized = filed_at_str.replace("T", " ")
        # Strip trailing Z if present
        if normalized.endswith("Z"):
            normalized = normalized[:-1]
        filed_date = datetime.fromisoformat(normalized)
        age_days = (now - filed_date).days
    except (ValueError, TypeError, AttributeError):
        age_days = 999  # unknown age → cold candidate

    # Recently filed = warm
    if age_days < COLD_DAYS:
        return "warm"

    # Old content in reference-class rooms stays warm
    if room in WARM_ROOMS:
        return "warm"

    # Everything else old → cold
    return "cold"


def main():
    parser = argparse.ArgumentParser(
        description="Auto-promote/demote MemPalace drawers between hot/warm/cold tiers (team.db)."
    )
    parser.add_argument("--execute", action="store_true", help="Actually update team.db")
    parser.add_argument("--report", action="store_true", help="Just show tier distribution")
    parser.add_argument("--wing", type=str, help="Filter to a specific wing")
    parser.add_argument("--db", type=str, default=DB_PATH, help=f"Path to team.db (default: {DB_PATH})")
    args = parser.parse_args()

    mode = "EXECUTE" if args.execute else ("REPORT" if args.report else "DRY RUN")
    print(f"{'=' * 60}")
    print(f"  MemPalace Tier Manager — {mode}")
    print(f"  Backend: team.db ({args.db})")
    print(f"  {datetime.now().isoformat()}")
    print(f"{'=' * 60}")
    print()

    conn = connect(args.db)
    now = datetime.now()

    # Fetch all drawers (or filtered by wing)
    sql = "SELECT id, drawer_id, wing, room, hall, tier, filed_at, metadata FROM drawers"
    params: tuple = ()
    if args.wing:
        sql += " WHERE wing = ?"
        params = (args.wing,)

    rows = conn.execute(sql, params).fetchall()
    total = len(rows)
    print(f"Total drawers: {total}")
    if total == 0:
        print("Nothing to do.")
        conn.close()
        return

    # Classify
    current_tiers = defaultdict(int)
    new_tiers = defaultdict(int)
    changes = defaultdict(list)  # (old_tier, new_tier) -> [(row, meta, new_tier)]

    for row in rows:
        old_tier = row["tier"] or "unset"
        meta = parse_metadata(row["metadata"])
        new_tier = get_tier(row, meta, now)

        current_tiers[old_tier] += 1
        new_tiers[new_tier] += 1

        if old_tier != new_tier:
            changes[(old_tier, new_tier)].append((row, meta, new_tier))

    # Report
    print(f"\n  Current tier distribution:")
    for tier in ["hot", "warm", "cold", "unset"]:
        count = current_tiers.get(tier, 0)
        if count > 0:
            print(f"    {tier:8} {count:5} ({count * 100 / total:.1f}%)")

    print(f"\n  New tier distribution:")
    for tier in ["hot", "warm", "cold"]:
        count = new_tiers.get(tier, 0)
        print(f"    {tier:8} {count:5} ({count * 100 / total:.1f}%)")

    total_changes = sum(len(v) for v in changes.values())
    print(f"\n  Changes needed: {total_changes}")
    if changes:
        print(f"\n  Transitions:")
        for (old, new), items in sorted(changes.items()):
            print(f"    {old:8} -> {new:8}: {len(items)}")

    if args.report:
        conn.close()
        return

    # Wing breakdown of changes
    if changes:
        wing_changes = defaultdict(lambda: defaultdict(int))
        for (old, new), items in changes.items():
            for row, _meta, _nt in items:
                wing_changes[row["wing"] or "?"][(old, new)] += 1
        print(f"\n  Changes by wing:")
        for wing in sorted(wing_changes.keys()):
            parts = ", ".join(f"{o}->{n}={c}" for (o, n), c in sorted(wing_changes[wing].items()))
            print(f"    {wing}: {parts}")

    if args.execute and total_changes > 0:
        print(f"\n  EXECUTING tier updates in team.db...")
        updated = 0
        now_iso = now.isoformat()
        try:
            # Single transaction across all batches for atomicity.
            with conn:
                for (old_tier, new_tier), items in changes.items():
                    for batch_start in range(0, len(items), BATCH_SIZE):
                        batch = items[batch_start:batch_start + BATCH_SIZE]
                        for row, meta, nt in batch:
                            new_meta = dict(meta)
                            new_meta["tier_updated_at"] = now_iso
                            if old_tier != "unset":
                                new_meta["tier_previous"] = old_tier
                            conn.execute(
                                "UPDATE drawers SET tier = ?, metadata = ? WHERE id = ?",
                                (nt, json.dumps(new_meta, ensure_ascii=False), row["id"]),
                            )
                            updated += 1
            print(f"  Updated: {updated} drawers (committed).")
        except sqlite3.Error as e:
            print(f"    ERROR: {e}", file=sys.stderr)
            sys.exit(1)
    elif not args.execute and total_changes > 0:
        print(f"\n  DRY RUN. Use --execute to apply.")

    conn.close()


if __name__ == "__main__":
    main()
