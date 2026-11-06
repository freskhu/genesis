# Databases with personal data: read in place, never copy

The typical failure: an agent copies a production database with people's personal data into a session scratchpad, to analyse it or to rehearse a migration, and afterwards nobody can say where the copy is. No script does it; agents do, by hand. There is no code to fix. There is behaviour, and this is it.

Technically it is a local read. For the business it is processing personal data outside the authorised place, with nobody able to say where the copies are.

## The test

> **Do I need to write to this database, or only read it?**

If only to read, there is no copy at all. Any copy created to read is a defect, however short the intent. One criterion, applied before writing the command, no exception list.

## 1. Which databases

- Any system database with names of workers, attendance records, absences, payroll codes, hourly rates, client contact details, lab values, symptoms or location.
- Exports and snapshots of the ERP.
- Production databases of the products the team builds (local, hosted or managed Postgres).
- A health database, if there is one (see `.claude/rules/health-data-boundary.md`). If it is a symbolic link, `cp` follows it: the copy comes out of the real file.

List yours in the table of section 4 and in `.claude/hooks/copy-guard.conf`. When in doubt about whether a file counts, it counts.

## 2. Do not copy

Refuse the copy to any destination outside the application folder: session scratchpad, `/tmp`, `outbox`, `Downloads`, `Desktop`, a development worktree, an attachment in a prompt to another agent.

Counts as a copy: `cp`, `rsync`, `scp`, `sqlite3 .backup`, `.dump`, `VACUUM INTO`, `pg_dump`, downloading over a network share, and loading the database into an HTML page.

A copy in a temporary folder outlives the session: macOS only sweeps `/private/tmp` at boot and by access age.

## 3. Read in place

```sh
sqlite3 "file:/path/to/app/data/app.db?mode=ro" "<query>"
```

`mode=ro` reads the WAL, does not write to the file and does not create `-shm`.

When the database is closed and clean, with no `-wal` or `-shm` next to it, this command fails with `unable to open database file (14)`: in WAL mode SQLite needs the `-shm` file and in read-only mode it cannot create it. **That failure does not authorise a copy.** In that state:

1. Confirm there is no pending write: `ls -l <db>-wal`. Absent or zero bytes means nothing pending.
2. Only then read with `?immutable=1`, which does without the `-shm`.

`immutable=1` **ignores the WAL**. With a non-empty `-wal` it returns stale state without warning, the worst possible result: a wrong answer that looks right. In that case ask the application owner for a checkpoint instead of reading.

In Postgres the equivalent is querying the live database with a read-only role inside a `READ ONLY` transaction, never a `pg_dump` to the local disk.

## 4. When a copy is really needed

Only to rehearse a write, a migration for example. Then:

1. The copy is born with `umask 077`, or `chmod 600` on the next line.
2. **It is born where the system's own retention routine sweeps it.** Never in the scratchpad, never in `/tmp`. The place is not the same in every system, and a folder named `backups/` is no guarantee of anything by itself: what counts is the glob of the routine.

   | Database | The copy is born in | Swept by |
   |---|---|---|
   | `<app>.db` | `data/backups/<app>-YYYYMMDD-HHMM[-<reason>].db` | `<retention script>`, scheduled by `<service manager entry>` |

   Fill one row per system. Check the routine's glob against the name you use: a file that looks like a backup, has no retention, and sits in a folder that looks right is the worst of the three states.
3. It is deleted at the end of the rehearsal by an exit `trap` in the script that creates it. A rehearsal that ends without deleting the copy has not ended.
4. A backup you want to keep has a written retention window, and the last copy before each migration stays until the next migration.

Whoever writes the migration script answers for step 3. A migration delivered without the line that deletes the copy is the origin of the next orphan copy.

`.claude/hooks/copy-guard.sh` is the deterministic edge of step 2: it lets the destinations listed as `allow` in `copy-guard.conf` through and blocks the rest, with a message saying where to put the copy.

## 5. Finding a copy out of place

Do not open it. Report to the orchestrator the path, size, permissions, date and owner. Removal needs the owner's named authorisation, because an `rm -rf` can delete a rehearsal in progress. A hygiene report that quotes a personnel row to prove the copy exists becomes the copy itself.

## 6. What is not a copy and passes

- Counts, averages and aggregates per section, without names.
- Anonymised, versionable fixtures.
- An example employee number, without a name, in an internal report.
- Table, column and view names.
- Architecture decisions.
- Generalised process lessons.

## Do not touch

This rule governs where database files with personal data live, and nothing else. What gets transcribed into drawers and `team.db` is governed by `.claude/rules/health-data-boundary.md` and `.claude/rules/financial-data-boundary.md`.
