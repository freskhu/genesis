#!/usr/bin/env python3
"""Tests for scripts/palace_audit.py on synthetic databases built from Database/schema.sql.

Run: python3 scripts/test_palace_audit.py
"""
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import palace_audit  # noqa: E402


def build_db(path: str, fixed_triggers: bool) -> None:
    conn = sqlite3.connect(path)
    with open(os.path.join(REPO, "Database", "schema.sql"), encoding="utf-8") as f:
        conn.executescript(f.read())
    if fixed_triggers:
        with open(os.path.join(REPO, "Database", "migrations",
                               "025_drawers_fts_delete_triggers.sql"), encoding="utf-8") as f:
            conn.executescript(f.read())
    conn.execute("INSERT INTO drawers (drawer_id, content, wing, room, hall) "
                 "VALUES ('d1', 'alpha bravo sensitiveword', 'w', 'r', 'hall_facts'), "
                 "('d2', 'delta echo', 'w', 'r', 'hall_facts')")
    conn.execute("UPDATE drawers SET content = 'alpha rewritten' WHERE drawer_id = 'd1'")
    conn.commit()
    conn.close()


class PalaceAuditTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def audit(self, fixed):
        path = os.path.join(self.tmp.name, f"t{int(fixed)}.db")
        build_db(path, fixed)
        return path, palace_audit.run_audit(path)

    def test_detector_proves_itself(self):
        self.assertTrue(palace_audit.capability_probe()["detector_proven"])

    def test_old_triggers_leave_orphan_tokens(self):
        _, rep = self.audit(fixed=False)
        fts = next(f for f in rep["findings"] if f["id"] == "fts_desync")
        self.assertEqual(fts["status"], "fail")
        self.assertIn("d1", fts["affected_drawer_ids"])
        self.assertIn("fts_desync", rep["invariants_broken"])

    def test_fixed_triggers_are_clean(self):
        _, rep = self.audit(fixed=True)
        fts = next(f for f in rep["findings"] if f["id"] == "fts_desync")
        self.assertEqual(fts["status"], "ok")
        self.assertEqual(fts["measured"], 0)

    def test_output_never_carries_terms(self):
        path, _ = self.audit(fixed=False)
        for flag in ([], ["--json"]):
            out = subprocess.run([sys.executable, os.path.join(HERE, "palace_audit.py"),
                                  "--db", path] + flag, capture_output=True, text=True)
            self.assertNotIn("sensitiveword", out.stdout + out.stderr)
            self.assertEqual(out.returncode, 1)

    def test_missing_db_is_exit_2(self):
        out = subprocess.run([sys.executable, os.path.join(HERE, "palace_audit.py"),
                              "--db", os.path.join(self.tmp.name, "none.db")],
                             capture_output=True, text=True)
        self.assertEqual(out.returncode, 2)

    def test_opens_read_only(self):
        path, _ = self.audit(fixed=True)
        conn = palace_audit.connect_ro(path)
        with self.assertRaises(sqlite3.OperationalError):
            conn.execute("INSERT INTO kg_entities (id, name) VALUES ('x', 'x')")
        conn.close()


if __name__ == "__main__":
    unittest.main(verbosity=1)
