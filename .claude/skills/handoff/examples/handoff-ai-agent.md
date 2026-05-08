# Handoff: Payment System Migration to Stripe

**Created:** 2026-02-10
**Author:** Claude Code session
**For:** AI Agent
**Status:** Ready to execute

---

## Summary

Migrating the billing system from Braintree to Stripe. The plan is fully shaped -- database schema changes are designed, the API wrapper is specced, and the migration strategy (dual-write with cutover) is decided. Implementation hasn't started. The receiving agent should execute the plan top-to-bottom.

## Project Context

SaaS application (Node.js/Express backend, PostgreSQL, React frontend). Monorepo structure. Currently using Braintree for subscriptions and one-time payments. ~2,400 active subscribers across 3 plan tiers. The app uses a `BillingService` abstraction layer, which makes the swap cleaner than it could be.

## The Plan

### Phase 1: Stripe Foundation (Days 1-2)
1. Install `stripe` package, add API keys to environment config
2. Create `src/services/billing/stripe.js` implementing the `BillingProvider` interface
3. Write unit tests for the Stripe provider against the same test suite as Braintree
4. Create Stripe webhook handler at `src/api/routes/stripe-webhooks.js`

### Phase 2: Database Schema (Day 3)
1. Add `stripe_customer_id` column to `users` table
2. Add `stripe_subscription_id` column to `subscriptions` table
3. Add `payment_provider` enum column to `payments` table
4. Create migration for all schema changes

### Phase 3: Dual-Write Period (Days 4-6)
1. Implement dual-write in `BillingService`
2. Build customer migration script (batches of 50 with retry logic)
3. Run migration script in staging, verify data integrity

### Phase 4: Cutover (Days 7-8)
1. Switch `BillingService` to Stripe-only
2. Run final migration batch
3. Verify webhook processing for renewals
4. Remove Braintree provider code

## Key Files

| File | Why It Matters |
|------|---------------|
| `src/services/billing/index.js` | BillingService abstraction -- main integration point |
| `src/services/billing/braintree.js` | Current provider -- reference for interface contract |
| `src/models/Subscription.js` | Needs new columns |
| `tests/services/billing.test.js` | Provider test suite -- new provider must pass these |

## Decisions Made

- **Dual-write over big-bang** -- 2,400 subscribers too many for a maintenance window
- **Keep BillingProvider interface unchanged** -- abstraction is solid
- **Batch migration in groups of 50** -- headroom for retries within Stripe's rate limit
- **No Braintree data deletion for 90 days** -- fallback during transition

## Constraints

- Do NOT modify `src/api/routes/billing.js` -- abstraction handles it
- Do NOT commit API keys
- Do NOT delete Braintree code until Phase 4
- All migrations must include rollback
- Migration script must be idempotent
