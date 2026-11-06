#!/usr/bin/env python3
"""
palace_audit.py -- read-only health audit of the memory palace in team.db.

Deterministic: no model, no network, no writes. Opens team.db with `mode=ro`, so any
write attempt is an error, not an effect.

CONTENT NEVER LEAVES THIS SCRIPT. The audit counts and classifies; it never prints
drawer text or index terms. Orphan tokens of a drawer rewritten to remove sensitive
content ARE the sensitive terms, and printing them in a report or a log would bring them
back through the audit channel. Terms appear as a fingerprint (truncated sha256) and a
length.

What it measures:
  L1 integrity (invariants)  db_integrity, fts_desync, vec_desync, drawers_empty
  L2 taxonomy                halls outside the canonical list, KG triples without entity

Why there is no FTS check by row count: drawers_fts is an external-content FTS5 table
(content='drawers'), so its row count is derived from `drawers` and is always equal, with
or without the trigger defect fixed by migration 025, which leaves orphan TOKENS, not
orphan rows. A check that cannot fail checks nothing. fts_desync rebuilds the index from
the same content in a temporary in-memory table, compares the two vocabularies term by
term, and confirms with MATCH which drawers are affected. Before trusting a clean result,
the same detector is proven on a throwaway database that reproduces the defect: if it
cannot detect it there, a clean result is reported as undetermined, never as ok.

Scoring: each check is worth its weight if ok, half if warn, zero if fail.
Exit codes:
  0  everything within thresholds
  1  score < --fail-under, OR an invariant failed
  2  execution error (missing DB, unexpected schema)

Usage:
  python3 scripts/palace_audit.py
  python3 scripts/palace_audit.py --json
  python3 scripts/palace_audit.py --fail-under 60 --quiet
  python3 scripts/palace_audit.py --db /path/team.db
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DB = os.path.join(os.path.dirname(SCRIPT_DIR), "Database", "team.db")
HALLS = ("hall_facts", "hall_events", "hall_discoveries", "hall_preferences",
         "hall_advice", "hall_diary")
LAYERS = {"L1": "integrity", "L2": "taxonomy"}


def connect_ro(db_path: str) -> sqlite3.Connection:
    if not os.path.exists(db_path):
        raise SystemExit(f"ERROR: team.db not found at {db_path}")
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.execute("PRAGMA busy_timeout = 10000")
    conn.execute("PRAGMA temp_store = MEMORY")   # drawer content never goes to temp files
    return conn


def one(conn, sql, params=()):
    row = conn.execute(sql, params).fetchone()
    return row[0] if row else None


def exists(conn, name, kind="table") -> bool:
    return bool(one(conn, "SELECT COUNT(*) FROM sqlite_master WHERE type=? AND name=?",
                    (kind, name)))


def fingerprint(term: str) -> str:
    return hashlib.sha256(term.encode("utf-8")).hexdigest()[:8]


def finding(cid, layer, weight, status, title, measured, threshold,
            severity="goal", detail=None, **extra):
    f = {"id": cid, "layer": layer, "weight": weight, "status": status,
         "severity": severity, "title": title, "measured": measured, "threshold": threshold}
    if detail:
        f["detail"] = detail
    f.update(extra)
    return f


# ------------------------------------------------------------------ FTS detector

def fts_spec(conn, fts_table="drawers_fts") -> dict:
    """Columns and tokenizer from the real DDL: a probe with another tokenizer would
    report false findings."""
    ddl = one(conn, "SELECT sql FROM sqlite_master WHERE name=?", (fts_table,))
    if not ddl:
        raise SystemExit(f"ERROR: index {fts_table} does not exist in this database")
    inner = ddl[ddl.index("(") + 1: ddl.rindex(")")]
    tok = re.search(r"tokenize\s*=\s*(['\"])(.*?)\1", inner)
    cols = []
    for raw in re.split(r",(?![^(]*\))", inner):
        part = raw.strip()
        if not part or re.match(r"^\w+\s*=", part):
            continue
        cols.append(part.split()[0].strip("'\"[]"))
    return {"columns": cols, "tokenize": tok.group(2) if tok else None}


def term_diff(conn, *, src_table, fts_table, spec, probe="audit_probe", max_pairs=50):
    """Phase 1: rebuild the index from current content and compare vocabularies
    (doc and cnt per term). Phase 2: for each suspicious term, MATCH in both indexes and
    diff the rowids, which gives concrete (term, drawer) pairs."""
    cols = ", ".join(spec["columns"])
    tok = f", tokenize='{spec['tokenize']}'" if spec["tokenize"] else ""
    conn.execute(f"DROP TABLE IF EXISTS temp.{probe}")
    conn.execute(f"CREATE VIRTUAL TABLE temp.{probe} USING fts5({cols}{tok})")
    conn.execute(f"INSERT INTO temp.{probe}(rowid, {cols}) SELECT id, {cols} FROM main.{src_table}")
    for name, sch, tbl in ((f"{probe}_rv", "main", fts_table), (f"{probe}_pv", "temp", probe)):
        conn.execute(f"DROP TABLE IF EXISTS temp.{name}")
        conn.execute(f"CREATE VIRTUAL TABLE temp.{name} USING fts5vocab('{sch}','{tbl}','row')")
    stale = conn.execute(f"""
        SELECT r.term FROM temp.{probe}_rv r LEFT JOIN temp.{probe}_pv p USING(term)
        WHERE p.term IS NULL OR r.cnt > p.cnt OR r.doc > p.doc ORDER BY r.term LIMIT ?""",
        (max_pairs,)).fetchall()
    missing = conn.execute(f"""
        SELECT p.term FROM temp.{probe}_pv p LEFT JOIN temp.{probe}_rv r USING(term)
        WHERE r.term IS NULL OR p.cnt > r.cnt OR p.doc > r.doc ORDER BY p.term LIMIT ?""",
        (max_pairs,)).fetchall()
    stale_pairs, missing_pairs = [], []
    for (term,) in stale + missing:
        q = '"' + term.replace('"', '""') + '"'
        real = {r[0] for r in conn.execute(
            f"SELECT rowid FROM main.{fts_table} WHERE {fts_table} MATCH ?", (q,))}
        fresh = {r[0] for r in conn.execute(
            f"SELECT rowid FROM temp.{probe} WHERE {probe} MATCH ?", (q,))}
        fp = fingerprint(term)
        stale_pairs += [{"rowid": rid, "term_fp": fp, "term_len": len(term)} for rid in sorted(real - fresh)]
        missing_pairs += [{"rowid": rid, "term_fp": fp, "term_len": len(term)} for rid in sorted(fresh - real)]
    return {"stale_terms": len(stale), "missing_terms": len(missing),
            "stale_pairs": stale_pairs, "missing_pairs": missing_pairs,
            "terms_real": one(conn, f"SELECT COUNT(*) FROM temp.{probe}_rv"),
            "terms_fresh": one(conn, f"SELECT COUNT(*) FROM temp.{probe}_pv"),
            "truncated": len(stale) >= max_pairs or len(missing) >= max_pairs}


def capability_probe() -> dict:
    """Reproduces the exact defect of the old trigger on a throwaway database and checks
    that the detector sees it."""
    db = sqlite3.connect(":memory:")
    db.executescript("""
        CREATE TABLE d (id INTEGER PRIMARY KEY, content TEXT NOT NULL);
        CREATE VIRTUAL TABLE d_fts USING fts5(content, content='d', content_rowid='id',
            tokenize='unicode61 remove_diacritics 2');
        CREATE TRIGGER d_ai AFTER INSERT ON d BEGIN
            INSERT INTO d_fts(rowid, content) VALUES (new.id, new.content);
        END;
        CREATE TRIGGER d_au AFTER UPDATE ON d BEGIN
            DELETE FROM d_fts WHERE rowid = old.id;
            INSERT INTO d_fts(rowid, content) VALUES (new.id, new.content);
        END;
        INSERT INTO d(id, content) VALUES (1, 'alpha bravo charlie'), (2, 'delta echo');
        UPDATE d SET content = 'alpha zulu' WHERE id = 1;
    """)
    res = term_diff(db, src_table="d", fts_table="d_fts", spec=fts_spec(db, "d_fts"),
                    probe="cap_probe", max_pairs=10)
    db.close()
    return {"detector_proven": bool(res["stale_pairs"]), "sqlite_version": sqlite3.sqlite_version}


# ------------------------------------------------------------------ checks

def check_db_integrity(conn, cap):
    res = one(conn, "PRAGMA integrity_check")
    return [finding("db_integrity", "L1", 8, "ok" if res == "ok" else "fail",
                    "database integrity_check", res, "ok", severity="invariant",
                    detail=f"sqlite {cap['sqlite_version']}")]


def check_fts_desync(conn, cap, max_pairs):
    if not exists(conn, "drawers_fts"):
        return [finding("fts_desync", "L1", 10, "warn", "FTS index in sync with drawers",
                        "undetermined", 0, detail="drawers_fts does not exist")]
    res = term_diff(conn, src_table="drawers", fts_table="drawers_fts",
                    spec=fts_spec(conn), max_pairs=max_pairs)
    stale, missing = len(res["stale_pairs"]), len(res["missing_pairs"])
    total = stale + missing
    if total:
        status = "fail"
    elif res["stale_terms"] + res["missing_terms"]:
        status = "warn"     # vocabularies differ but no drawer located: never ok
    elif not cap["detector_proven"]:
        status = "warn"     # undetermined: the detector did not prove itself
    else:
        status = "ok"
    ids = []
    if total:
        rowids = sorted({p["rowid"] for p in res["stale_pairs"] + res["missing_pairs"]})[:20]
        ph = ",".join("?" * len(rowids))
        ids = [r[0] for r in conn.execute(f"SELECT drawer_id FROM drawers WHERE id IN ({ph})", rowids)]
    detail = (f"{res['terms_real']} terms in the index vs {res['terms_fresh']} in the content; "
              f"orphan tokens={stale}, missing tokens={missing}; "
              f"detector proven={'yes' if cap['detector_proven'] else 'NO'}")
    if res["truncated"]:
        detail += "; list truncated by --max-pairs"
    return [finding("fts_desync", "L1", 10, status,
                    "FTS index in sync (MATCH sweep, not a row count)", total, 0,
                    severity="invariant", detail=detail, affected_drawer_ids=ids,
                    stale_pairs=stale, missing_pairs=missing)]


def check_vec_desync(conn):
    """Missing and orphan embeddings. Uses sqlite-vec when available; otherwise reads the
    shadow table drawers_vec_rowids by its `rowid` column (its `id` column is NULL for a
    vec0 table with an integer primary key, and a NOT IN over NULLs is never true)."""
    table = key = via = None
    if exists(conn, "drawers_vec"):
        try:
            conn.enable_load_extension(True)
            import sqlite_vec  # noqa: PLC0415
            sqlite_vec.load(conn)
            conn.enable_load_extension(False)
            conn.execute("SELECT drawer_rowid FROM drawers_vec LIMIT 1")
            table, key, via = "drawers_vec", "drawer_rowid", "extension"
        except Exception:
            table = None
    if table is None and exists(conn, "drawers_vec_rowids"):
        table, key, via = "drawers_vec_rowids", "rowid", "shadow table"
    if table is None:
        return [finding("vec_desync", "L1", 8, "warn", "vector index in sync with drawers",
                        "undetermined", 0, detail="drawers_vec unreadable and no shadow table")]
    missing = one(conn, f"SELECT COUNT(*) FROM drawers d WHERE NOT EXISTS "
                        f"(SELECT 1 FROM {table} v WHERE v.{key} = d.id)")
    orphan = one(conn, f"SELECT COUNT(*) FROM {table} v WHERE NOT EXISTS "
                       f"(SELECT 1 FROM drawers d WHERE d.id = v.{key})")
    return [finding("vec_desync", "L1", 8, "ok" if missing + orphan == 0 else "fail",
                    "vector index in sync with drawers", missing + orphan, 0,
                    severity="invariant",
                    detail=f"without embedding={missing}, orphan vectors={orphan} (via {via})")]


def check_drawers_empty(conn):
    n = one(conn, "SELECT COUNT(*) FROM drawers WHERE content IS NULL OR trim(content)=''")
    return [finding("drawers_empty", "L1", 4, "ok" if n == 0 else "fail",
                    "drawers without content", n, 0, severity="invariant")]


def check_taxonomy(conn):
    ph = ", ".join("?" * len(HALLS))
    n = one(conn, f"SELECT COUNT(*) FROM drawers WHERE hall IS NULL OR hall NOT IN ({ph})", HALLS)
    out = [finding("taxonomy_halls", "L2", 5, "ok" if n == 0 else "warn",
                   "drawers with a hall outside the canonical list", n, 0,
                   note="reclassifying is a semantic judgement: the audit counts, it does not move")]
    # Entity ids follow palace.py kg-add: lower(name) with spaces as underscores.
    orphan = one(conn, """
        SELECT COUNT(*) FROM kg_triples t
        WHERE lower(replace(t.subject,' ','_')) NOT IN (SELECT id FROM kg_entities)
           OR lower(replace(t.object,' ','_'))  NOT IN (SELECT id FROM kg_entities)""")
    out.append(finding("kg_orphans", "L2", 5, "ok" if orphan == 0 else "warn",
                       "KG triples without an entity", orphan, 0,
                       detail=f"{one(conn, 'SELECT COUNT(*) FROM kg_triples')} triples, "
                              f"{one(conn, 'SELECT COUNT(*) FROM kg_entities')} entities"))
    return out


def run_audit(db_path=DEFAULT_DB, max_pairs=50) -> dict:
    conn = connect_ro(db_path)
    cap = capability_probe()
    try:
        findings = (check_db_integrity(conn, cap) + check_fts_desync(conn, cap, max_pairs)
                    + check_vec_desync(conn) + check_drawers_empty(conn) + check_taxonomy(conn))
        drawers = one(conn, "SELECT COUNT(*) FROM drawers")
        generated_at = one(conn, "SELECT strftime('%Y-%m-%dT%H:%M:%SZ','now')")
    finally:
        conn.close()
    points = {"ok": 1.0, "warn": 0.5, "fail": 0.0}
    layers: dict = {}
    for f in findings:
        lay = layers.setdefault(f["layer"], {"name": LAYERS.get(f["layer"], f["layer"]),
                                             "weight": 0, "earned": 0.0})
        lay["weight"] += f["weight"]
        lay["earned"] += f["weight"] * points[f["status"]]
    for lay in layers.values():
        lay["score"] = round(100.0 * lay["earned"] / lay["weight"], 1) if lay["weight"] else 100.0
    total_w = sum(l["weight"] for l in layers.values())
    score = round(100.0 * sum(l["earned"] for l in layers.values()) / total_w, 1) if total_w else 0.0
    broken = [f["id"] for f in findings if f["severity"] == "invariant" and f["status"] == "fail"]
    return {"generated_at": generated_at, "db": db_path, "drawers": drawers, "score": score,
            "layers": dict(sorted(layers.items())), "findings": findings,
            "invariants_broken": broken, "capability": cap}


ICON = {"ok": "ok  ", "warn": "WARN", "fail": "FAIL"}


def render(rep: dict) -> str:
    out = [f"=== palace audit -- {rep['generated_at']} ===",
           f"db: {rep['db']}  drawers: {rep['drawers']}  score: {rep['score']}/100"]
    for lid, lay in rep["layers"].items():
        out.append(f"\n[{lid} {lay['name']}] {lay['score']}/100")
        for f in rep["findings"]:
            if f["layer"] != lid:
                continue
            inv = " (invariant)" if f["severity"] == "invariant" else ""
            out.append(f"  {ICON[f['status']]}  {f['title']}{inv}")
            out.append(f"        measured: {f['measured']}   threshold: {f['threshold']}")
            if f.get("detail"):
                out.append(f"        {f['detail']}")
            if f.get("affected_drawer_ids"):
                out.append(f"        affected drawers: {', '.join(f['affected_drawer_ids'])}")
    if rep["invariants_broken"]:
        out.append("\nBROKEN INVARIANTS: " + ", ".join(rep["invariants_broken"]))
    return "\n".join(out)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Read-only, deterministic audit of the memory palace.")
    p.add_argument("--db", default=DEFAULT_DB)
    p.add_argument("--fail-under", type=float, default=0.0,
                   help="exit 1 if the overall score is below this value")
    p.add_argument("--max-pairs", type=int, default=50,
                   help="cap on suspicious terms taken to the MATCH sweep")
    p.add_argument("--json", action="store_true")
    p.add_argument("--quiet", action="store_true", help="verdict line only")
    a = p.parse_args(argv)
    try:
        rep = run_audit(a.db, a.max_pairs)
    except SystemExit as e:
        print(e, file=sys.stderr)
        return 2
    except (sqlite3.Error, OSError) as e:
        print(f"ERROR: {type(e).__name__}: {e}", file=sys.stderr)
        return 2
    failed = rep["score"] < a.fail_under or bool(rep["invariants_broken"])
    rep["fail_under"] = a.fail_under
    rep["verdict"] = "FAIL" if failed else "PASS"
    if a.json:
        print(json.dumps(rep, ensure_ascii=False, indent=2))
    elif a.quiet:
        print(f"palace audit: {rep['verdict']} score={rep['score']} "
              f"fail-under={a.fail_under} invariants={rep['invariants_broken'] or 'ok'}")
    else:
        print(render(rep))
        print(f"\nverdict: {rep['verdict']} (score {rep['score']}, fail-under {a.fail_under})")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
