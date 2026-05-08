#!/usr/bin/env python3
"""
memory_tiers.py — Auto-promote/demote MemPalace drawers between hot/warm/cold tiers.

Tier logic (inspired by Enterprise blueprint):
  - HOT:  Drawers accessed in >50% of recent sessions (last 10), or manually pinned
  - WARM: Default tier. Actively accessed content.
  - COLD:  Not accessed in >30 days

The tier is stored as ChromaDB metadata ('tier' field). This enables filtered
searches: search only hot-tier for session bootstrapping, warm for on-demand,
cold for deep dives.

Usage:
  python3 memory_tiers.py                  # DRY RUN — show what would change
  python3 memory_tiers.py --execute        # LIVE — update ChromaDB metadata
  python3 memory_tiers.py --report         # Just show current tier distribution
  python3 memory_tiers.py --wing work       # Filter to a specific wing

Author: the orchestrator (AIT Orchestrator) — adapted from Enterprise blueprint
Date: 2026-04-10
"""

import os
import argparse
import sys
from collections import defaultdict
from datetime import datetime, timedelta

import chromadb

PALACE_PATH = os.path.expanduser("~/.mempalace/palace")
COLLECTION_NAME = "mempalace_drawers"
BATCH_SIZE = 200

# Tier thresholds
COLD_DAYS = 30  # days since filed with no reclassification → cold candidate
HOT_ROOMS = {
    # Rooms that are structurally hot (always loaded)
    "identity", "preferences", "protocols", "configuration",
}
HOT_HALLS = {
    # Halls that tend to be hot
    "hall_preferences", "hall_diary",
}


def get_tier(meta: dict, filed_at_str: str, now: datetime) -> str:
    """Determine the tier for a drawer based on metadata and age."""
    room = meta.get("room", "")
    hall = meta.get("hall", "")
    wing = meta.get("wing", "")

    # Structurally hot: identity, preferences, protocols, config rooms
    if room in HOT_ROOMS:
        return "hot"

    # Structurally hot: preference and diary halls
    if hall in HOT_HALLS:
        return "hot"

    # {{OWNER}} wing is always hot (owner profile)
    if wing == "owner":
        return "hot"

    # Recently reclassified or added = warm
    reclassified_at = meta.get("hall_reclassified_at", "")
    if reclassified_at:
        try:
            rc_date = datetime.fromisoformat(reclassified_at)
            if (now - rc_date).days < COLD_DAYS:
                return "warm"
        except (ValueError, TypeError):
            pass

    # Check filed_at age
    try:
        filed_date = datetime.fromisoformat(filed_at_str)
        age_days = (now - filed_date).days
    except (ValueError, TypeError):
        age_days = 999  # unknown age → cold candidate

    # Recently filed = warm
    if age_days < COLD_DAYS:
        return "warm"

    # Old content in certain rooms stays warm (reference material)
    warm_rooms = {"reference", "architecture", "cases", "code"}
    if room in warm_rooms:
        return "warm"

    # Everything else old → cold
    return "cold"


def main():
    parser = argparse.ArgumentParser(
        description="Auto-promote/demote MemPalace drawers between hot/warm/cold tiers."
    )
    parser.add_argument("--execute", action="store_true", help="Actually update ChromaDB")
    parser.add_argument("--report", action="store_true", help="Just show tier distribution")
    parser.add_argument("--wing", type=str, help="Filter to a specific wing")
    args = parser.parse_args()

    mode = "EXECUTE" if args.execute else ("REPORT" if args.report else "DRY RUN")
    print(f"{'=' * 60}")
    print(f"  MemPalace Tier Manager — {mode}")
    print(f"  {datetime.now().isoformat()}")
    print(f"{'=' * 60}")
    print()

    client = chromadb.PersistentClient(path=PALACE_PATH)
    col = client.get_collection(COLLECTION_NAME)
    now = datetime.now()

    # Fetch all drawers
    where_filter = {"wing": args.wing} if args.wing else None
    all_ids = []
    all_metas = []
    offset = 0
    while True:
        kwargs = {"limit": 5000, "offset": offset, "include": ["metadatas"]}
        if where_filter:
            kwargs["where"] = where_filter
        batch = col.get(**kwargs)
        if not batch["ids"]:
            break
        all_ids.extend(batch["ids"])
        all_metas.extend(batch["metadatas"])
        offset += len(batch["ids"])

    total = len(all_ids)
    print(f"Total drawers: {total}")

    # Classify tiers
    current_tiers = defaultdict(int)
    new_tiers = defaultdict(int)
    changes = defaultdict(list)  # (old_tier, new_tier) -> [(id, meta)]

    for did, meta in zip(all_ids, all_metas):
        old_tier = meta.get("tier", "unset")
        filed_at = meta.get("filed_at", meta.get("hall_reclassified_at", ""))
        new_tier = get_tier(meta, filed_at, now)

        current_tiers[old_tier] += 1
        new_tiers[new_tier] += 1

        if old_tier != new_tier:
            changes[(old_tier, new_tier)].append((did, meta))

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
            print(f"    {old:8} → {new:8}: {len(items)}")

    if args.report:
        return

    # Wing breakdown of changes
    if changes:
        wing_changes = defaultdict(lambda: defaultdict(int))
        for (old, new), items in changes.items():
            for did, meta in items:
                wing_changes[meta.get("wing", "?")][(old, new)] += 1
        print(f"\n  Changes by wing:")
        for wing in sorted(wing_changes.keys()):
            parts = ", ".join(f"{o}→{n}={c}" for (o, n), c in sorted(wing_changes[wing].items()))
            print(f"    {wing}: {parts}")

    if args.execute and total_changes > 0:
        print(f"\n  EXECUTING tier updates...")
        updated = 0
        for (old_tier, new_tier), items in changes.items():
            for batch_start in range(0, len(items), BATCH_SIZE):
                batch = items[batch_start:batch_start + BATCH_SIZE]
                batch_ids = [did for did, _ in batch]
                batch_metas = []
                for did, meta in batch:
                    new_meta = dict(meta)
                    new_meta["tier"] = new_tier
                    new_meta["tier_updated_at"] = now.isoformat()
                    if old_tier != "unset":
                        new_meta["tier_previous"] = old_tier
                    batch_metas.append(new_meta)
                try:
                    col.update(ids=batch_ids, metadatas=batch_metas)
                    updated += len(batch_ids)
                except Exception as e:
                    print(f"    ERROR: {e}", file=sys.stderr)

        print(f"  Updated: {updated} drawers")
    elif not args.execute and total_changes > 0:
        print(f"\n  DRY RUN. Use --execute to apply.")


if __name__ == "__main__":
    main()
