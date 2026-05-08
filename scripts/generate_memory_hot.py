#!/usr/bin/env python3
"""
generate_memory_hot.py — Generate memory-hot.md from team.db unified database.

This is the anti-forgetting mechanism. It creates a markdown briefing that gets
loaded at every session start, containing:
  1. Owner identity (from KG)
  2. Active priorities and pending tasks
  3. Recent decisions and session activity
  4. Hot-tier drawer summaries (most important knowledge)
  5. Team status
  6. Active KG facts

The output is written to .claude/memory-hot.md and referenced from CLAUDE.md
so it's automatically loaded at session start.

Usage:
  python3 generate_memory_hot.py              # Generate memory-hot.md
  python3 generate_memory_hot.py --stdout     # Print to stdout instead of file

Author: the orchestrator (AIT Orchestrator)
Date: 2026-04-10
"""

import argparse
import sys
from datetime import datetime

import apsw
import sqlite_vec

# Owner display name. Set via /genesis or edit here.
OWNER_NAME = os.environ.get("GENESIS_OWNER_NAME", "Owner")

TEAM_DB = "Database/team.db"
OUTPUT_PATH = "<project root>/.claude/memory-hot.md"


def connect():
    db = apsw.Connection(TEAM_DB)
    db.enableloadextension(True)
    sqlite_vec.load(db)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA busy_timeout=5000")
    return db


def section_identity(db):
    """Owner identity from KG."""
    lines = [f"## Owner — {OWNER_NAME}"]
    facts = db.execute("""
        SELECT subject, predicate, object FROM kg_triples
        WHERE (subject = 'owner' OR subject = '{{OWNER}}') AND valid_to IS NULL
        ORDER BY predicate
    """).fetchall()
    if facts:
        for s, p, o in facts:
            lines.append(f"- {p.replace('_', ' ')}: {o.replace('_', ' ')}")
    return "\n".join(lines)


def section_tasks(db):
    """Pending and in-progress tasks."""
    lines = ["## Pending Tasks"]
    try:
        tasks = db.execute("""
            SELECT t.id, t.title, t.status, t.priority,
                   tm.name AS assigned_to
            FROM tasks t
            LEFT JOIN team_members tm ON t.assigned_to = tm.id
            WHERE t.status IN ('pending', 'in_progress', 'blocked')
            ORDER BY
                CASE t.priority WHEN 'urgent' THEN 1 WHEN 'high' THEN 2 WHEN 'normal' THEN 3 ELSE 4 END,
                t.created_at DESC
            LIMIT 10
        """).fetchall()
        if tasks:
            for tid, title, status, priority, assignee in tasks:
                assignee_str = f" → {assignee}" if assignee else ""
                lines.append(f"- [{status}] **{title}** ({priority}){assignee_str}")
        else:
            lines.append("- Sem tarefas pendentes")
    except Exception:
        lines.append("- (erro ao consultar tasks)")
    return "\n".join(lines)


def section_recent_activity(db):
    """Last 10 significant activities."""
    lines = ["## Actividade Recente (últimas 48h)"]
    try:
        activities = db.execute("""
            SELECT action, summary, occurred_at
            FROM activity_history
            WHERE occurred_at > datetime('now', '-48 hours')
              AND action NOT IN ('session_start', 'session_end')
            ORDER BY occurred_at DESC
            LIMIT 10
        """).fetchall()
        if activities:
            for action, summary, ts in activities:
                date = ts[:16] if ts else "?"
                lines.append(f"- [{date}] {action}: {summary[:120]}")
        else:
            lines.append("- Sem actividade nas últimas 48h")
    except Exception:
        lines.append("- (erro ao consultar activity_history)")
    return "\n".join(lines)


def section_recent_decisions(db):
    """Recent decisions from hot drawers in hall_facts."""
    lines = ["## Recent Decisions"]
    try:
        decisions = db.execute("""
            SELECT wing, room, substr(content, 1, 200) AS preview, filed_at
            FROM drawers
            WHERE hall = 'hall_facts'
              AND tier = 'hot'
            ORDER BY filed_at DESC
            LIMIT 5
        """).fetchall()
        if decisions:
            for wing, room, preview, filed_at in decisions:
                date = filed_at[:10] if filed_at else "?"
                clean = preview.replace("\n", " ").strip()
                lines.append(f"- [{wing}/{room}] {clean}...")
        else:
            lines.append("- Sem decisões hot-tier recentes")
    except Exception:
        lines.append("- (erro ao consultar drawers)")
    return "\n".join(lines)


def section_team(db):
    """Active team members."""
    lines = ["## Equipa Activa"]
    try:
        members = db.execute("""
            SELECT name, role FROM team_members
            WHERE is_active = 1
            ORDER BY name
        """).fetchall()
        if members:
            member_list = [f"{name} ({role})" for name, role in members]
            lines.append(f"- {len(members)} membros: {', '.join(member_list)}")
        else:
            lines.append("- (sem membros activos)")
    except Exception:
        lines.append("- (erro ao consultar team_members)")
    return "\n".join(lines)


def section_projects(db):
    """Active projects from KG."""
    lines = ["## Projectos Activos"]
    try:
        projects = db.execute("""
            SELECT object, predicate FROM kg_triples
            WHERE subject = 'owner' AND predicate IN ('builds', 'manages', 'runs', 'studies_at')
              AND valid_to IS NULL
            ORDER BY predicate
        """).fetchall()
        if projects:
            for obj, pred in projects:
                lines.append(f"- {pred.replace('_', ' ')}: **{obj.replace('_', ' ')}**")
        else:
            lines.append("- (sem projectos no KG)")
    except Exception:
        lines.append("- (erro ao consultar KG)")
    return "\n".join(lines)


def section_palace_stats(db):
    """Palace/memory stats."""
    lines = ["## Estado da Memória"]
    try:
        stats = db.execute("SELECT * FROM v_palace_stats").fetchone()
        if stats:
            lines.append(f"- Drawers: {stats[0]} total ({stats[1]} hot, {stats[2]} warm, {stats[3]} cold)")
            lines.append(f"- KG: {stats[6]} factos activos")
            lines.append(f"- Diários: {stats[7]} entries")
    except Exception:
        lines.append("- (erro ao consultar stats)")
    return "\n".join(lines)


def section_procedural(db):
    """Top procedural patterns."""
    lines = ["## Padrões Aprendidos (top 5)"]
    try:
        patterns = db.execute("""
            SELECT name, trigger_pattern, action, success_rate
            FROM procedural_memory
            WHERE success_count + failure_count > 0
            ORDER BY success_rate DESC, success_count DESC
            LIMIT 5
        """).fetchall()
        if patterns:
            for name, trigger, action, rate in patterns:
                lines.append(f"- **{name or trigger[:40]}** (success: {rate:.0%}): {action[:80]}")
        else:
            lines.append("- Sem padrões com execuções registadas ainda")
    except Exception:
        lines.append("- (erro ao consultar procedural_memory)")
    return "\n".join(lines)


def section_inbox(db):
    """Unprocessed inbox files."""
    lines = ["## Inbox Não Processado"]
    try:
        import os
        inbox_path = "<project root>/Team Inbox"
        if os.path.isdir(inbox_path):
            all_files = os.listdir(inbox_path)
            processed = set()
            for row in db.execute("SELECT filename FROM processed_inbox_files"):
                processed.add(row[0])
            unprocessed = [f for f in all_files if f not in processed and not f.startswith(".")]
            if unprocessed:
                for f in unprocessed[:5]:
                    lines.append(f"- **NOVO:** {f}")
                if len(unprocessed) > 5:
                    lines.append(f"- ... e {len(unprocessed) - 5} mais")
            else:
                lines.append("- Tudo processado")
    except Exception:
        lines.append("- (erro ao verificar inbox)")
    return "\n".join(lines)


def generate():
    db = connect()
    now = datetime.now().strftime("%Y-%m-%d %H:%M")

    sections = [
        f"# Memory Hot — Briefing Automático",
        f"*Gerado: {now} | Este ficheiro é regenerado automaticamente.*",
        "",
        section_identity(db),
        "",
        section_projects(db),
        "",
        section_tasks(db),
        "",
        section_inbox(db),
        "",
        section_recent_activity(db),
        "",
        section_recent_decisions(db),
        "",
        section_team(db),
        "",
        section_procedural(db),
        "",
        section_palace_stats(db),
    ]

    return "\n".join(sections)


def main():
    parser = argparse.ArgumentParser(description="Generate memory-hot.md briefing")
    parser.add_argument("--stdout", action="store_true", help="Print to stdout")
    args = parser.parse_args()

    content = generate()

    if args.stdout:
        print(content)
    else:
        with open(OUTPUT_PATH, "w") as f:
            f.write(content)
        print(f"Generated: {OUTPUT_PATH}")
        print(f"Size: {len(content)} chars, {content.count(chr(10))} lines")


if __name__ == "__main__":
    main()
