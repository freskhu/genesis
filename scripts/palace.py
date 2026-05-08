#!/usr/bin/env python3
"""
palace.py — Unified palace operations on team.db (sqlite-vec).

Replaces all MemPalace MCP tools with direct SQL against team.db.
Single file, no external dependencies beyond apsw + sqlite-vec + sentence-transformers.

Usage:
  python3 palace.py search "VRIN {{COMPETITOR}}"                    # Hybrid search (vector + FTS5)
  python3 palace.py search "rules of thumb" --wing work --hall hall_facts --limit 5
  python3 palace.py search "DCA executor" --mode keyword     # FTS5 only
  python3 palace.py search "trading approach" --mode vector   # Vector only

  python3 palace.py add --wing ai_team --room architecture --hall hall_facts --content "..."
  python3 palace.py add --wing ai_team --room architecture --hall hall_facts --file path/to/file.md

  python3 palace.py kg-add "{{OWNER}}" "builds" "{{PROJECT}}"
  python3 palace.py kg-query "{{OWNER}}"
  python3 palace.py kg-invalidate "{{OWNER}}" "builds" "old_project"
  python3 palace.py kg-stats

  python3 palace.py diary-write "the orchestrator" "SESSION:2026-04-10|summary|★★★"
  python3 palace.py diary-read "the orchestrator" --last 5

  python3 palace.py status
  python3 palace.py hot                                       # Show hot-tier drawers

Author: the orchestrator (AIT Orchestrator)
Date: 2026-04-10
"""

import argparse
import hashlib
import struct
import sys
from datetime import datetime

import apsw
import sqlite_vec

TEAM_DB = "Database/team.db"
EMBED_MODEL = "paraphrase-multilingual-mpnet-base-v2"
EMBED_DIMS = 768
RERANK_MODEL = "cross-encoder/ms-marco-MiniLM-L-6-v2"

_model = None
_reranker = None


def get_model():
    global _model
    if _model is None:
        from sentence_transformers import SentenceTransformer
        _model = SentenceTransformer(EMBED_MODEL)
    return _model


def get_reranker():
    global _reranker
    if _reranker is None:
        from sentence_transformers import CrossEncoder
        _reranker = CrossEncoder(RERANK_MODEL)
    return _reranker


def serialize_f32(vec) -> bytes:
    return struct.pack(f"{len(vec)}f", *vec)


def connect():
    db = apsw.Connection(TEAM_DB)
    db.enableloadextension(True)
    sqlite_vec.load(db)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA busy_timeout=5000")
    db.execute("PRAGMA foreign_keys=ON")
    return db


# ============================================================
# SEARCH
# ============================================================

def cmd_search(args):
    db = connect()
    query = args.query
    limit = args.limit or 5
    mode = args.mode or "hybrid"

    results = []

    if mode in ("vector", "hybrid"):
        model = get_model()
        qvec = model.encode(query)

        where_parts = []
        params = [serialize_f32(qvec)]

        sql = f"""
            SELECT d.id, d.wing, d.room, d.hall, d.tier,
                   substr(d.content, 1, 300) AS preview,
                   v.distance
            FROM drawers_vec v
            JOIN drawers d ON d.id = v.drawer_rowid
            WHERE v.embedding MATCH ? AND k = {limit * 2}
        """
        if args.wing:
            sql += " AND d.wing = ?"
            params.append(args.wing)
        if args.hall:
            sql += " AND d.hall = ?"
            params.append(args.hall)
        if args.room:
            sql += " AND d.room = ?"
            params.append(args.room)
        if args.tier:
            sql += " AND d.tier = ?"
            params.append(args.tier)

        sql += f" ORDER BY v.distance LIMIT {limit}"

        for row in db.execute(sql, params):
            results.append({
                "id": row[0], "wing": row[1], "room": row[2], "hall": row[3],
                "tier": row[4], "preview": row[5], "distance": row[6], "source": "vector"
            })

    if mode in ("keyword", "hybrid"):
        where_extra = ""
        fts_params = [query]
        if args.wing:
            where_extra += " AND d.wing = ?"
            fts_params.append(args.wing)
        if args.hall:
            where_extra += " AND d.hall = ?"
            fts_params.append(args.hall)

        fts_params.append(limit)

        fts_sql = f"""
            SELECT d.id, d.wing, d.room, d.hall, d.tier,
                   snippet(drawers_fts, 0, '>>>', '<<<', '...', 40) AS preview,
                   rank
            FROM drawers_fts f
            JOIN drawers d ON d.id = f.rowid
            WHERE drawers_fts MATCH ?{where_extra}
            ORDER BY rank
            LIMIT ?
        """

        for row in db.execute(fts_sql, fts_params):
            # Deduplicate with vector results
            if not any(r["id"] == row[0] for r in results):
                results.append({
                    "id": row[0], "wing": row[1], "room": row[2], "hall": row[3],
                    "tier": row[4], "preview": row[5], "distance": row[6], "source": "fts5"
                })

    # Reranking stage (if we have enough results and not keyword-only)
    if len(results) > 1 and mode != "keyword" and not args.no_rerank:
        reranker = get_reranker()
        pairs = [(query, r["preview"]) for r in results]
        scores = reranker.predict(pairs)
        for i, r in enumerate(results):
            r["rerank_score"] = float(scores[i])
        results.sort(key=lambda x: x["rerank_score"], reverse=True)

    # Print results
    reranked = len(results) > 1 and mode != "keyword" and not args.no_rerank
    print(f"\nSearch: \"{query}\" (mode={mode}, reranked={'yes' if reranked else 'no'}, results={len(results)})")
    if args.wing:
        print(f"Filters: wing={args.wing}", end="")
        if args.hall:
            print(f", hall={args.hall}", end="")
        if args.room:
            print(f", room={args.room}", end="")
        print()

    for i, r in enumerate(results[:limit]):
        src = "V" if r["source"] == "vector" else "K"
        rscore = f" rerank={r['rerank_score']:.2f}" if "rerank_score" in r else ""
        dist = f"dist={r['distance']:.3f}" if isinstance(r['distance'], float) else f"rank={r['distance']}"
        print(f"\n  [{src}] {r['wing']}/{r['room']}/{r['hall']} ({r['tier']}) {dist}{rscore}")
        preview = r['preview'].replace('\n', ' ').strip()[:200]
        print(f"      {preview}")


# ============================================================
# ADD DRAWER
# ============================================================

def cmd_add(args):
    db = connect()
    model = get_model()

    content = args.content
    if args.file:
        with open(args.file, "r") as f:
            content = f.read()

    if not content:
        print("ERROR: --content or --file required")
        sys.exit(1)

    wing = args.wing
    room = args.room
    hall = args.hall or "hall_discoveries"
    tier = args.tier or "warm"
    source = args.source or ""

    drawer_id = f"drawer_{wing}_{room}_{hashlib.sha256((wing + room + content[:100]).encode()).hexdigest()[:24]}"

    # Check duplicate
    existing = db.execute("SELECT id FROM drawers WHERE drawer_id = ?", (drawer_id,)).fetchone()
    if existing:
        print(f"Already exists: {drawer_id}")
        return

    # Embed
    vec = model.encode(content)

    db.execute(
        """INSERT INTO drawers (drawer_id, content, wing, room, hall, tier, source_file, added_by, filed_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (drawer_id, content, wing, room, hall, tier, source, "palace.py", datetime.now().isoformat())
    )
    rowid = db.execute("SELECT last_insert_rowid()").fetchone()[0]
    db.execute("INSERT INTO drawers_vec (drawer_rowid, embedding) VALUES (?, ?)",
               (rowid, serialize_f32(vec)))

    print(f"Added: {drawer_id} → {wing}/{room}/{hall} ({tier})")


# ============================================================
# KNOWLEDGE GRAPH
# ============================================================

def cmd_kg_add(args):
    db = connect()
    s, p, o = args.subject, args.predicate, args.object
    valid_from = args.valid_from or datetime.now().strftime("%Y-%m-%d")

    tid = f"t_{s}_{p}_{o}_{hashlib.sha256(f'{s}{p}{o}'.encode()).hexdigest()[:12]}"

    # Check duplicate
    existing = db.execute(
        "SELECT id FROM kg_triples WHERE subject=? AND predicate=? AND object=? AND valid_to IS NULL",
        (s, p, o)).fetchone()
    if existing:
        print(f"Already exists: {s} → {p} → {o}")
        return

    # Ensure entities
    for name in [s, o]:
        eid = name.lower().replace(" ", "_")
        if not db.execute("SELECT id FROM kg_entities WHERE id=?", (eid,)).fetchone():
            db.execute("INSERT INTO kg_entities (id, name) VALUES (?, ?)", (eid, name))

    db.execute(
        "INSERT INTO kg_triples (id, subject, predicate, object, valid_from, confidence) VALUES (?,?,?,?,?,1.0)",
        (tid, s, p, o, valid_from))
    print(f"Added: {s} → {p} → {o} (from {valid_from})")


def cmd_kg_query(args):
    db = connect()
    entity = args.entity
    results = db.execute("""
        SELECT subject, predicate, object, valid_from
        FROM kg_triples
        WHERE (subject = ? OR object = ?) AND valid_to IS NULL
        ORDER BY predicate
    """, (entity, entity)).fetchall()
    print(f"\nKG facts for '{entity}' ({len(results)}):")
    for s, p, o, vf in results:
        print(f"  {s} → {p} → {o}" + (f" (since {vf})" if vf else ""))


def cmd_kg_invalidate(args):
    db = connect()
    s, p, o = args.subject, args.predicate, args.object
    now = datetime.now().strftime("%Y-%m-%d")
    updated = db.execute(
        "UPDATE kg_triples SET valid_to = ? WHERE subject=? AND predicate=? AND object=? AND valid_to IS NULL",
        (now, s, p, o))
    count = db.execute("SELECT changes()").fetchone()[0]
    print(f"Invalidated {count} fact(s): {s} → {p} → {o}")


def cmd_kg_stats(args):
    db = connect()
    total = db.execute("SELECT COUNT(*) FROM kg_triples").fetchone()[0]
    active = db.execute("SELECT COUNT(*) FROM kg_triples WHERE valid_to IS NULL").fetchone()[0]
    entities = db.execute("SELECT COUNT(*) FROM kg_entities").fetchone()[0]
    preds = db.execute("SELECT DISTINCT predicate FROM kg_triples WHERE valid_to IS NULL ORDER BY predicate").fetchall()
    print(f"\nKG Stats: {total} total, {active} active, {entities} entities")
    print(f"Predicates: {', '.join(p[0] for p in preds)}")


# ============================================================
# DIARY
# ============================================================

def cmd_diary_write(args):
    db = connect()
    db.execute("INSERT INTO diary_entries (agent_name, topic, content) VALUES (?, ?, ?)",
               (args.agent, args.topic or "general", args.entry))
    print(f"Diary written: {args.agent} ({args.topic or 'general'})")


def cmd_diary_read(args):
    db = connect()
    last = args.last or 10
    entries = db.execute("""
        SELECT agent_name, topic, content, created_at FROM diary_entries
        WHERE agent_name = ?
        ORDER BY created_at DESC LIMIT ?
    """, (args.agent, last)).fetchall()
    print(f"\nDiary for '{args.agent}' (last {last}):")
    for name, topic, content, ts in entries:
        print(f"  [{ts[:16]}] ({topic}) {content[:120]}")


# ============================================================
# STATUS & HOT
# ============================================================

def cmd_status(args):
    db = connect()
    stats = db.execute("SELECT * FROM v_palace_stats").fetchone()
    wings = db.execute("SELECT wing, COUNT(*) FROM drawers GROUP BY wing ORDER BY COUNT(*) DESC").fetchall()
    halls = db.execute("SELECT hall, COUNT(*) FROM drawers GROUP BY hall ORDER BY COUNT(*) DESC").fetchall()

    print(f"\n{'='*50}")
    print(f"  Palace Status (sqlite-vec in team.db)")
    print(f"{'='*50}")
    print(f"  Drawers:  {stats[0]} ({stats[1]} hot, {stats[2]} warm, {stats[3]} cold)")
    print(f"  Wings:    {stats[4]}")
    print(f"  Rooms:    {stats[5]}")
    print(f"  KG facts: {stats[6]}")
    print(f"  Diaries:  {stats[7]}")
    print(f"\n  By wing:")
    for w, c in wings:
        print(f"    {w:20} {c}")
    print(f"\n  By hall:")
    for h, c in halls:
        print(f"    {h:20} {c}")


def cmd_hot(args):
    db = connect()
    drawers = db.execute("""
        SELECT wing, room, hall, substr(content, 1, 150) AS preview
        FROM drawers WHERE tier = 'hot'
        ORDER BY wing, room
        LIMIT 20
    """).fetchall()
    print(f"\nHot-tier drawers ({len(drawers)} shown):")
    for w, r, h, preview in drawers:
        print(f"  [{w}/{r}/{h}] {preview.replace(chr(10), ' ')[:100]}...")


# ============================================================
# MAIN
# ============================================================

def main():
    parser = argparse.ArgumentParser(description="Palace operations on team.db")
    sub = parser.add_subparsers(dest="cmd")

    # search
    s = sub.add_parser("search", help="Hybrid search")
    s.add_argument("query", type=str)
    s.add_argument("--wing", type=str)
    s.add_argument("--room", type=str)
    s.add_argument("--hall", type=str)
    s.add_argument("--tier", type=str)
    s.add_argument("--limit", type=int, default=5)
    s.add_argument("--mode", choices=["hybrid", "vector", "keyword"], default="hybrid")
    s.add_argument("--no-rerank", action="store_true", help="Skip reranking stage")

    # add
    a = sub.add_parser("add", help="Add a drawer")
    a.add_argument("--wing", required=True)
    a.add_argument("--room", required=True)
    a.add_argument("--hall", default="hall_discoveries")
    a.add_argument("--tier", default="warm")
    a.add_argument("--content", type=str)
    a.add_argument("--file", type=str)
    a.add_argument("--source", type=str, default="")

    # kg-add
    ka = sub.add_parser("kg-add", help="Add KG triple")
    ka.add_argument("subject")
    ka.add_argument("predicate")
    ka.add_argument("object")
    ka.add_argument("--valid-from", type=str)

    # kg-query
    kq = sub.add_parser("kg-query", help="Query KG entity")
    kq.add_argument("entity")

    # kg-invalidate
    ki = sub.add_parser("kg-invalidate", help="Invalidate KG triple")
    ki.add_argument("subject")
    ki.add_argument("predicate")
    ki.add_argument("object")

    # kg-stats
    sub.add_parser("kg-stats", help="KG statistics")

    # diary-write
    dw = sub.add_parser("diary-write", help="Write diary entry")
    dw.add_argument("agent")
    dw.add_argument("entry")
    dw.add_argument("--topic", default="general")

    # diary-read
    dr = sub.add_parser("diary-read", help="Read diary entries")
    dr.add_argument("agent")
    dr.add_argument("--last", type=int, default=10)

    # status
    sub.add_parser("status", help="Palace status")

    # hot
    sub.add_parser("hot", help="Show hot-tier drawers")

    args = parser.parse_args()
    if not args.cmd:
        parser.print_help()
        return

    cmds = {
        "search": cmd_search, "add": cmd_add,
        "kg-add": cmd_kg_add, "kg-query": cmd_kg_query,
        "kg-invalidate": cmd_kg_invalidate, "kg-stats": cmd_kg_stats,
        "diary-write": cmd_diary_write, "diary-read": cmd_diary_read,
        "status": cmd_status, "hot": cmd_hot,
    }
    cmds[args.cmd](args)


if __name__ == "__main__":
    main()
