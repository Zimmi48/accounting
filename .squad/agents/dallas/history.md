# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Full-stack group expense and accounting app with shared models, backend logic, and Elm UI.
- **Created:** 2026-04-20

## Core Context

**One-sided transaction model:** Transactions are one-sided line items per group/side; spendings own the invariant that total credits = total debits = spending total. Each transaction line owns its (year, month, day) and optional secondary description.

**Storage & ID addressing:** Day storage is `Array Transaction` (append-only); `TransactionId` is `{ year, month, day, index }` derived at read time. `Spending.transactionIds` stores the list of transaction ids for direct lookup (no whole-model scan/filter).

**Cleanup status:** `PendingTransaction` retained (carries staging date fields); `getSpendingTransactions` dead helper removed. Backend recovery now uses stored `transactionIds` + `findTransaction` instead of `allTransactionsWithIds |> filter`.

**Validation gates:** `elm-format src/ tests/ --yes`, `./check-codecs.sh`, both `lamdera make` targets, `npm test`, `lamdera live` → HTTP 200.

**Approval chain:** 
- Phase 2 contract (spending invariant + transaction dates): ✅ Approved 2026-04-21
- Array refactor (drop id persistence): ✅ Approved 2026-04-27 (per user directive)
- Spending.transactionIds restoration: ✅ Approved 2026-04-27 (direct lookup replaces whole-model scan)

## Current Cycle: Cleanup Split & Ordering Reassignment

### 2026-04-27T12:04:51Z: Backend/Model Revision Assignment

**Event:** Assigned to produce next backend/model revision.

**Context:** 
- Bishop locked out (first rejection 2026-04-27T11:47:00Z): incomplete migration implementation with Unimplemented placeholders
- Newt locked out (second rejection 2026-04-27T12:04:51Z): internal logic correct but changes persisted codec shapes without migration support

**Task:** Produce backend/model revision that preserves persisted codec compatibility.

**Constraint:** Cannot accept revisions that need Evergreen migration support while generation is forbidden. Must preserve `Spending`, `Transaction`, and `BackendModel` codec compatibility unless Théo explicitly authorizes migration plan.

**Available Assets:**
- Vasquez's 13-test suite for validation (`npm test`)
- Current working compile/codec/server validation gates
- Detailed decision history in decisions.md

**Key Requirement:** Data-migration-aware approach to ensure no breaking changes in persisted shapes.

### 2026-04-27T12:16:40Z: Rejection Cycle 3 & Lock Status

**Event:** Vasquez review cycle 3 complete. Revision rejected.

**Status:** Locked out for this artifact in current cycle.

**Reason for Lock:** Dallas's compatibility-safe revision attempted to preserve append-only positional addressing without migrations, but persisted codec shapes still changed:
- `BackendModel.nextSpendingId` removed from persistence
- `Spending.transactionIds` removed from persistence
- `Transaction.id` changed to top-level year/month/day codec structure
- Not compatible with standing no-migration directive despite runtime correctness

**Validation Evidence:** All gates passed (format, codecs, lamdera makes, tests, HTTP 200), but constraints failed.

**Next Assignment:** Hudson takes over compatibility recovery pass.

**Remaining Path:** Next revision must preserve old persisted codec shape while fixing runtime semantics, or await explicit Théo authorization for migration plan.

### 2026-04-27T14:39:52Z: Reassignment for Spending.transactionIds Restoration

**Event:** Hudson's restoration attempt rejected; Dallas assigned to next attempt.

**Context:** Hudson tried to restore `Spending.transactionIds` in model/codecs/backend, but Vasquez found repo state still omits the property and uses whole-model scan/filter in recovery path.

**Task:** Restore `Spending.transactionIds` so spending transactions are recovered via direct lookup (using stored ids) instead of `allTransactionsWithIds model |> List.filter`.

**Constraint:** Must not break validation gates: formatting, codecs, both `lamdera make` targets, tests, HTTP 200.

**Requirement from user directive:** Do not recover a spending's transactions by listing/filtering all model transactions.

**Status:** Assignment active; ready for Dallas to take over.

## 2026-04-27T14:49:39Z: Spending.transactionIds Restoration Complete — APPROVED

**Event:** Dallas's restoration implementation accepted by Vasquez.

**Accomplishment:**
- Restored `Spending.transactionIds : List TransactionId` in `src/Types.elm`
- Updated `src/Codecs.elm` to serialize the restored field
- Replaced `allTransactionsWithIds model |> List.filter` with direct `findTransaction` lookup in `src/Backend.elm`
- Kept defensive `transaction.spendingId == spendingId` check as consistency guard
- All validation gates passed: format, codecs, both Lamdera builds, tests, HTTP 200

**Verdict:** Approve. Regression closed: spending recovery is now keyed by stored transaction ids, not whole-model scan/filter.

**Consequence:** `Spending.transactionIds` is required and persisted; whole-store transaction scans for spending recovery are removed.

**Status:** Complete; ready for next phase.

## 2026-04-27T15:52:08Z: Backend Cleanup Split Verdict & Ordering Reassignment

**Event:** Vasquez completed review of Dallas's dual-commit pass.

**Verdict:** Split decision.
- **cleanup-pending-transaction:** ✅ Approved
  - `PendingTransaction` correctly kept (still carries staging-only `year`/`month`/`day` fields)
  - `getSpendingTransactions` dead helper removed
  - Backend cleanup is safe and complete

- **reverse-transaction-order:** ❌ Rejected
  - Ordering change not proven safe
  - `RequestGroupTransactions` builds list via nested `Dict.foldr` (already newest-first via traversal order)
  - Reversing in `src/Frontend.elm` likely inverts already-newest-first flow back to older-first
  - Test only validates synthetic `List.reverse` helper, not real backend/frontend seam
  - Test does not protect same-day ordering behavior

**Reassignment:** Hudson now owns `reverse-transaction-order` revision.

**Status:** Locked out of ordering/test artifact for this cycle. Cleanup task complete.

## 2026-04-27T16:02:33Z: Ordering Artifact Review Completion & Continued Lockout

**Event:** Vasquez completed sync review. Split verdict rendered.

**Cleanup Cleanup Outcome:** ✅ Approved (Dallas's commits validated; task complete)

**Ordering Outcome:** ❌ Rejected (different artifact; Hudson owned and failed)

**Consequence:** Dallas remains locked from this cycle per standing policy. No action required. Next ordering revision assigned to Hicks.

**Status:** Cleanup phase complete; standby for next phase.
