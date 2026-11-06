# Health data boundary

Drawers in the memory palace and rows in `team.db` are searchable by every agent of the team, including the one that writes to clients and the one that writes public posts. The owner's health data does not need to be within their reach. If the owner uses the team for anything health-related, all clinical content lives in a separate database (for example `Database/clinical.db`, owned by the database owner), is classified `lens`, and is never citable in an external deliverable.

This rule exists because intention does not survive the act of writing. The typical failure: a drawer is saved with the sentence "this drawer holds only the architecture decision, no clinical data", and minutes later another drawer is saved with medication doses and lab values. The rule does not fail because it is ignored; it fails because it depends on someone remembering it at the right moment.

## The test

> **If the agent that writes emails to clients read this drawer in full, would it learn something clinical about the owner?**

If yes, the drawer is not saved like that. It is rewritten before saving. One line, applied before every `palace.py add` that touches health. No second criterion, no exception list.

## 1. Never in drawers or in `team.db`

Refuse, in any wing, room or hall:

- Lab values, with or without unit, with or without reference range.
- Doses, dosing schedules, dose phases, start and end dates of treatment.
- Drug names, brand or active ingredient.
- Named diagnoses.
- Exam dates and results.
- Clinical scores.
- Imaging, endoscopy or pathology findings.
- Agent sub-specialties when they reveal the diagnosis by inference. Write the broad field ("clinical nutrition", "exercise physiology") and keep the sub-specialty in the spec, which is a file, not a drawer.

The name of a specific exam counts as clinical data: "I said there was no <exam name> in the files" already reveals the exam was ordered.

## 2. Fine to save

- Architecture decisions: a separate database, STRICT tables and why, versioned migrations.
- Modelling requirements without values: "medication follows staged phases over months, so the table needs phases with intervals" passes; the drug name and the doses do not.
- Table, view and column names.
- Dashboard categories: "out-of-range lab parameters with history" is a category name, not a value.
- Process lessons, generalised: "search every file in the folder by term before claiming an exam is absent" passes; the same lesson with the exam name does not.
- Pointers to the health database, its schema doc and the spec.

The dry pointer is the canonical reference:

> Health tracking approved by the owner on <date>. Spec in `Team/_briefs/<spec>.md`. Own database, schema in its own doc. All clinical content is lens and lives there, never in drawers.

## 3. The `lens` label is not enough protection

`palace.py search` prefixes `[LENS]` only for drawers in the owner wings and rooms configured in `OWNER_WINGS` / `OWNER_ROOMS` of `scripts/palace.py`. A drawer in `ai_team/decisions` gets no prefix at all. Saving clinical content outside those rooms and counting on the automatic label is saving it unlabelled. Corollary: permission given for an identity drawer does not carry over to a decisions drawer with the same content.

## 4. Correction procedure

When clinical content is already saved:

1. **Backup first.** A copy of `team.db` in `Database/backups/`, named `team-YYYYMMDD-HHMMSS-<reason>.db`, mode `600`. Never in the session scratchpad or `/tmp`: `team.db` holds names and contacts of people outside the team, so a copy in a temporary folder is a copy of personal data that outlives the session (`.claude/rules/personal-data-db-access.md`). Restoring this file is the rollback.
2. Rewrite `content` with an `UPDATE drawers SET content=? WHERE id=?`, keeping the architecture decisions and process lessons. Do not delete the drawer: the trail is lost.
3. **Re-embed.** Delete and reinsert the `drawers_vec` row with `palace.get_model().encode(new_content)` and `palace.serialize_f32`. Without this, vector search keeps scoring the drawer by its old clinical meaning. `drawers_vec` needs the `sqlite_vec` extension, so this runs in Python through `palace.connect()`, never in the `sqlite3` CLI.
4. **Verify by `MATCH`, never by count.** Run `python3 scripts/palace_audit.py`: the `fts_desync` check must report `0` orphan and `0` missing tokens. Then sweep the corrected term on both sides, `SELECT id FROM drawers WHERE content LIKE '%<term>%'` and `SELECT rowid FROM drawers_fts WHERE drawers_fts MATCH '<term>'`, both empty. If orphan tokens show up, repair once with `INSERT INTO drawers_fts(drawers_fts) VALUES('rebuild');` and verify again. (Migration `025_drawers_fts_delete_triggers.sql` fixes the trigger defect that used to leave the old tokens behind.)

   Do not compare the row count of `drawers_fts` with `drawers`. `drawers_fts` is an external-content FTS5 table, so its row count is derived from `drawers` and is always equal, with or without the defect. The defect leaves orphan **tokens**, not orphan **rows**. A check that cannot fail gives the feeling of having been done and leaves the clinical term searchable.
5. Regenerate the briefing: `python3 scripts/generate_memory_hot.py`.
6. Once step 4 is clean, the backup leaves the disk or stays under the retention of `Database/backups/`. Whoever writes the correction script answers for that.

## Do not touch

The health database belongs to the database owner. This rule covers what goes into drawers and `team.db`, and nothing else.
