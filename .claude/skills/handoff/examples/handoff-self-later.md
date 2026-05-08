# Handoff: Full-Text Search with Meilisearch

**Created:** 2026-02-10
**Status:** Paused -- pick up from here

---

## Where I Left Off

Writing the search indexing worker. Meilisearch is running, schema is configured, API endpoint returns results. But the background indexing job that keeps search in sync with Postgres isn't done -- it indexes on create but not on update/delete. Stopped because sync logic needs careful thought about ordering guarantees.

## The Plan

Replace Postgres `ILIKE` search with Meilisearch for `posts` and `comments`. Three parts: Meilisearch setup, Search API, Index sync via BullMQ.

## What's Working

- Meilisearch running in Docker (port 7700)
- Both indices configured with field weights
- `GET /api/search?q=term` endpoint works with highlights
- Bulk indexing script works (~8 seconds for 10K posts)
- Tests pass for search endpoint and bulk indexing

## What's Not Working Yet

- **Index sync on update/delete** -- only handles `created` events
- **Stale result links** -- deleted posts still appear in search, 404 on click
- **Search pagination** -- returns all results, `offset`/`limit` not wired

## My Current Thinking

Event-driven via existing model hooks (not polling or CDC). `afterUpdate` and `afterDestroy` hooks already exist for activity feed. BullMQ handles ordering within a queue.

## Decisions I've Made

- **Meilisearch over Elasticsearch** -- simpler, good enough for <100K docs
- **Separate indices per model** -- unified index had messy field mapping
- **BullMQ for async sync** -- search indexing shouldn't block HTTP response
- **Highlight format: `<mark>` tags** -- Meilisearch returns natively

## Things I Tried That Didn't Work

- **Unified search index** -- relevance got weird (posts have titles, comments don't)
- **Synchronous indexing** -- added 200-400ms to every create
- **`pg_trgm` extension** -- poor typo tolerance, ugly query syntax

## Next Time I Pick This Up

1. Add `afterUpdate`/`afterDestroy` hooks dispatching events to BullMQ
2. Handle update/delete events in `SearchIndexWorker`
3. Write sync tests (create, update, verify; delete, verify gone)
4. Add pagination query params
5. Add frontend 404 guard for stale results
6. Full manual test of sync
7. Update Docker docs for Meilisearch container
