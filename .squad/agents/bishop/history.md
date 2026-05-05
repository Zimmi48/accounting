# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Group expense and accounting app with Lamdera backend and evergreen migrations.
- **Created:** 2026-04-19

## Learnings

- Initial roster assignment: Backend, model changes, and Lamdera migration ownership.
- 2026-04-19: Spending/transaction split landed in `src/Types.elm`, `src/Backend.elm`, and `src/Evergreen/Migrate/V26.elm`. Backend storage now separates `spendings : Dict SpendingId Spending` from dated `Day.transactions : List Transaction`, with stable `SpendingId`/`TransactionId` counters on `BackendModel`.
- Backend edit/delete keeps the old append-only pattern: spendings and transactions are marked `Replaced`/`Deleted`, totals are removed from aggregates, and edits create a fresh spending plus fresh transactions.
- Current frontend contract preserves the existing dialog by sending a singleton `transactions` list with spending-date defaults and empty `secondaryDescription`; backend normalization still merges by `(date, secondaryDescription)` bucket, summing credits and debits separately by group.
- Evergreen V26 migrates each legacy day spending into one stored spending plus one transaction with empty secondary description, while frontend/session migration intentionally resets fragile client-side edit/delete state to safe defaults.
- Codec workflow remains `./check-codecs.sh --regenerate`, and migration validation succeeded with `lamdera check --force` after adding `src/Evergreen/V26/Types.elm` and `src/Evergreen/Migrate/V26.elm`.
- 2026-04-21: Codec parity fixes can be generation-only; for the current model shape, `./check-codecs.sh --regenerate` refreshed `src/Codecs.elm` without touching `src/Types.elm`, `src/Backend.elm`, or any `src/Evergreen/` files, and validation stayed on `elm-format`, both `lamdera make` targets, and `lamdera live` HTTP 200.
- 2026-05-05: Mixed-sign creditor spendings fail in `src/Backend.elm` before persistence, not in the dialog submit gate. `Frontend.canSubmitSpending` and `dialogTransactions` already pass signed amounts through, so backend normalization/validation must keep non-zero signed transaction lines and only drop exact zero merges; regression coverage now lives in `tests/BackendTests.elm`.

## 2026-04-21: Phase 2 Contract Correction Approved

- **Session timestamp:** 2026-04-21T06:49:24Z
- **Commit:** `862817b` — Codec parity refresh complete
- **Role:** Ensured codec alignment in `src/Codecs.elm` after model corrections
- **Outcome:** All review gates green; part of approved Hudson + Bishop stack
- **Contract:** Spending owns total invariant; transaction lines own dates/secondary descriptions
- **Next phase:** Await data model finalization for Evergreen migration

- 2026-04-27: In the current split model, `BackendModel.nextSpendingId` was redundant because `spendings` is append-only and `SpendingId` is just the array index; creation now uses `Array.length model.spendings` in `src/Backend.elm`, and codec parity dropped the field in `src/Types.elm` / `src/Codecs.elm`.
- 2026-04-27: `Transaction.id` remains necessary in `src/Types.elm` because a spending fans out into multiple dated records whose visible fields are not unique enough for edit/delete/detail reassembly; concise comments now document that contract near `Spending.transactionIds`, `Transaction.id`, and `TransactionId.index`.
- 2026-04-27: The id-instability bug in `src/Backend.elm` came from persisting `TransactionId.index` but still resolving transactions through the current day-list position (`listGet`). The safer fix is to match by stored `transaction.id` instead; earlier code was less exposed because it regenerated positional ids when building list responses instead of persisting them.
- 2026-04-27: Evaluating `Day.transactions` as an `Array` showed slot-based `TransactionId.index` would only stay stable if day storage becomes strictly append-only with no compaction or ordered inserts. That could move persisted line identity out of `Transaction.id` and into `Spending.transactionIds` plus traversal context, but it does not remove the need for durable per-transaction identity; for the current Lamdera model, matching stored `transaction.id` remains the lower-risk option versus adding a new day-array invariant or scanning by `spendingId`.
- 2026-04-27: Théo approved exact transaction addressing via append-only day positions. `src/Types.elm` now keeps `TransactionId` only as a derived `{ year, month, day, index }` reference, `src/Backend.elm` appends same-day writes and derives ids with `List.indexedMap`, and `src/Evergreen/Migrate/V26.elm` rebuilds legacy day spendings into append-only positional transactions while resetting fragile frontend edit state.

## 2026-04-27T10:37:26Z: Backend ID Stability Session

- **Spawned:** Bishop (Backend Dev) to fix transaction-ID instability regression
- **Request:** Keep `Transaction.id` persisted, remove `nextSpendingId`, update codecs, add explanatory comments, change lookup to match stored `transaction.id` instead of mutable day-list position
- **Fixes Applied:**
  - Removed redundant `BackendModel.nextSpendingId` from `src/Types.elm`; allocation now uses `Array.length model.spendings`
  - Updated backend codec in `src/Codecs.elm` to remove `nextSpendingId` field
  - Added inline code comments in `src/Backend.elm` explaining transaction-ID stability and why stored `Transaction.id` is necessary
  - Changed `findTransaction` to match stored `transaction.id` value instead of treating `TransactionId.index` as current day-list position
  - Adapted transaction lookup and edit/delete flows to use stored-ID matching
- **Decision:** Merged to decisions.md (2026-04-27 "Backend ID Stability")
- **Validation:** Compiles; codecs validated; development server HTTP 200; no Evergreen migrations (feature branch only)
- **Status:** Completed

## 2026-04-27T11:02:33Z: Array vs List Backend Tradeoff Analysis

- **Session timestamp:** 2026-04-27T11:02:33Z
- **Orchestration:** Completed with Ripley (sync review)
- **Task:** Evaluate concrete data-structure tradeoffs in Elm/Lamdera model for day-transaction storage
- **Output:** Tradeoff matrix and backend-specific concerns documented in decisions.md
- **Key Finding:** Array would stabilize indices if paired with strict append-only discipline everywhere; current backend mostly append-only already
- **Tradeoff:** Schema/invariant change cost exceeds local lookup optimization benefit; recommend explicit stored-ID approach for now
- **Decision merged:** bishop-array-tradeoffs.md tradeoff guidance merged to decisions.md (2026-04-27)

## 2026-04-27T11:31:00Z: Append-Only Positional Transaction IDs

- **Request:** Remove stored/precomputed transaction ids now that exact addressing can rely on append-only day positions.
- **Files:** `src/Types.elm`, `src/Backend.elm`, `src/Codecs.elm`, `src/Evergreen/Migrate/V26.elm`
- **Outcome:** Stored `Transaction.id` and `Spending.transactionIds` were removed; backend now derives `TransactionId` from each day's append-only list order and finds spending membership via `transaction.spendingId`.
- **Validation:** `elm-format src/ --yes`, `./check-codecs.sh`, both `lamdera make` targets, `lamdera check --force` (migration compile succeeded; final step blocked only by missing `lamdera login`), and `lamdera live --port=8002` with HTTP 200.

## 2026-04-27T11:31:00Z: Append-Only Positional Transaction IDs

- **Request:** Remove stored/precomputed transaction ids now that exact addressing can rely on append-only day positions.
- **Files:** `src/Types.elm`, `src/Backend.elm`, `src/Codecs.elm`, `src/Evergreen/Migrate/V26.elm`
- **Outcome:** Stored `Transaction.id` and `Spending.transactionIds` were removed; backend now derives `TransactionId` from each day's append-only list order and finds spending membership via `transaction.spendingId`.
- **Validation:** `elm-format src/ --yes`, `./check-codecs.sh`, both `lamdera make` targets, `lamdera check --force` (migration compile succeeded; final step blocked only by missing `lamdera login`), and `lamdera live --port=8002` with HTTP 200.

## 2026-04-27T11:47:00Z: Artifact Rejection & Lock

**Event:** Backend/model refactor artifact rejected in review.

**Reason:** `src/Evergreen/Migrate/V26.elm` incomplete with Unimplemented placeholders risking data loss.

**Status:** Locked out of this artifact for current cycle. Newt assigned to complete.

**Reviewer:** Vasquez (Tester)

## 2026-04-28T08:18:47Z: Backend spending status churn investigation

- **Session:** Parallel investigation of test failures and backend performance
- **Role:** Backend analysis to trace spending edit/delete paths
- **Finding:** `setSpendingStatus` is called exactly once per operation (correct). Real inefficiency is in transaction-status and removal traversals over active transactions, not in repeated setSpendingStatus calls.
- **Pattern:** Two separate traversals of transaction metadata:
  1. `setTransactionStatuses`: Nested foldl over transactionIds to update status in year→month→day structure
  2. `removeTransactionFromModel` loop: Another traversal to update aggregates
- **Cost:** O(N) nested Dict updates per operation
- **Optimization Option:** Combine both concerns into single traversal to reduce from O(2N) to O(N)
- **Recommendation:** Profile first. Current performance acceptable for typical spendings (<100 transactions). No refactoring without profiling evidence.
- **Status:** Investigation complete; decision merged to decisions.md 

**Note:** Vasquez's test suite (13 tests) now available for future validation.

## 2026-04-27T12:04:51Z: Second Rejection & Dallas Reassignment

**Event:** Newt's replacement revision rejected by Vasquez. Both Bishop and Newt locked out; Dallas assigned.

**What Passed:**
- Append-only slot logic internally correct
- All validation gates: compile, codecs, tests, server HTTP 200
- No Evergreen files regenerated

**Why It Fails:**
- Persisted `Spending` and `Transaction` codec shapes changed without migration support
- Removes `BackendModel.nextSpendingId`, `Spending.transactionIds`
- Replaces `Transaction.id : TransactionId` with top-level year/month/day
- Breaking change for Lamdera state and exported JSON
- Under no-migration directive, unacceptable

**Next Assignment:** Dallas to produce backend/model revision with codec compatibility preservation.

## Delete/Edit Performance Investigation

**Request:** "When deleting or editing a spending, `setSpendingStatus` is run many times for no reason (as many times as there are active transactions instead of just once)."

**Trace & Finding:**
- `setSpendingStatus` is called exactly **once** per delete/edit operation (lines 163, 192 in current Backend.elm)
- Pattern uses three-phase approach: (1) mark spending Replaced/Deleted, (2) mark all transactions Replaced/Deleted via nested foldl, (3) loop N times to remove from aggregates
- `setTransactionStatuses` uses nested Dict.update traversal that grows O(N) but is architecturally necessary to reach year→month→day→transaction structure
- No hidden loops calling `setSpendingStatus` within transaction iteration

**Why it feels redundant:** The design separates status updates (one foldl through transactionIds) from aggregate removal (another foldl through activeTransactions). Both traverse the transaction list but do different work—a performance optimization would combine them into one loop, but risks introducing bugs in deeply nested Dict manipulation.

**Assessment:** Code is correct as-is. `setSpendingStatus` is already called once. The architectural concern is the redundant traversal in `setTransactionStatuses` + `removeTransactionFromModel` loop, not multiple calls to `setSpendingStatus`.

**Safe optimization candidate:** Inline transaction-status update into the `removeTransactionFromModel` foldl to eliminate the separate `setTransactionStatuses` call entirely. Current cost is acceptable for typical <100 transaction spendings; only worth pursuing if profiling shows measurable impact.

## 2026-04-28T14:15:00Z: Spending Lifecycle Totals Test Review

- **Request:** Investigate failing lifecycle-total tests to determine if they reflect user-visible bugs or internal inconsistencies.
- **Tests:** Two failing tests in `BackendTests.elm` (lines 126-169):
  1. "same-day add/edit/delete keeps exact stored totals aligned with active transactions"
  2. "cross-period edits and deletion keep year, month, and day totals aligned"
- **Finding:** Both tests are **correct and reveal a real backend bug**.

**Root Cause:** When `removeTransactionFromModel` removes a transaction:
  1. It negates the transaction's amounts: `Dict.map (\_ (Amount x) -> Amount -x) groupCredits`
  2. Passes negated amounts to `addToTotalGroupCredits` to zero them out
  3. `addAmounts` correctly produces `Amount 0` when the amounts cancel
  4. **Bug:** Zero-valued entries are never removed from `totalGroupCredits` dicts at any level (global, yearly, monthly, daily)
  5. These "ghost" entries persist indefinitely in the model

**Data Integrity Impact:**
- Global, yearly, monthly, and daily `totalGroupCredits` dicts accumulate zero entries that should be absent
- `Person.belongsTo` set is also never cleaned up—group keys remain even after all that person's amounts in that group are zero

**User Visibility:** Partially hidden by UI filtering:
- `RequestUserGroups` (line 266) filters creditors with `credit > 0`
- `RequestUserGroups` (line 266) filters debitors with `credit < 0`
- Zero amounts are naturally excluded from these lists, so users don't see phantom groups
- **However:** This is fragile—proper fix requires cleaning up at the source, not relying on UI filters

**Precise Manual Reproduction (if UI filters weren't present):**
1. Create group "Trip" with Alice and Bob as members
2. Record expense: "Dinner", total 1200, Alice pays (credit 1200), Trip owes (debit 1200, split 50/50)
3. Delete the "Dinner" expense
4. **Expected:** Backend totals dicts should be empty for Trip at all levels
5. **Actual:** Stored totals contain `Trip → {Alice: 0, Bob: 0}` and similar zero entries at year/month/day levels
6. Alice's `belongsTo` still includes the Trip key

**Verdict:** Internal data corruption bug (model not cleaned on delete), partially masked by UI filters but represents accumulating garbage in stored state.

## 2026-04-29T06:59:52Z: Lifecycle Totals Bug Validation

- **Session:** Orchestrated split review with Ripley
- **Task:** Validate whether failing tests expose real backend bugs or false positives
- **Finding:** Backend has real internal data corruption bug:
  - `removeTransactionFromModel` negates amounts correctly but leaves zero-valued entries in totals dicts
  - Leakage sites: global/yearly/monthly/daily `totalGroupCredits` + `Person.belongsTo` set
  - Root cause: No cleanup when entries hit zero
- **User Impact:** Partially hidden by UI filters (RequestUserGroups filters non-zero amounts). Fragile; needs source cleanup.
- **Fix Requirements:** (1) Remove dict entries when they hit zero, (2) Clean up `Person.belongsTo`, (3) Audit model queries for zero-entry assumptions
- **Orchestration status:** Under review; awaiting decision on cleanup strategy and scope
- **Artifact:** `.squad/decisions/inbox/bishop-test-validation-lifecycle-totals.md` (archived to decisions.md)
- 2026-04-29: Export repair tooling now lives in `scripts/validate_totals.py`. It targets the current `/json` export shape from `src/Types.elm` / `src/Codecs.elm`, replays active transactions via `Transaction.spendingId`, validates spending totals plus root/year/month/day `totalGroupCredits` and `Person.belongsTo`, and writes fixes to a separate JSON file instead of mutating source exports in place.

## 2026-04-29T07:25:19Z: Export Validator Implementation (Background)

- **Task:** Add export validator and fixer script with associated documentation
- **Deliverables:** `scripts/validate_totals.py`, README usage section
- **Scope Decision:** Only rewrite derived fields (`totalGroupCredits` at all scopes, `persons.*.belongsTo`)
- **Rationale:** Only recomputable fields are safe to mutate; spendings, transactions, statuses must be surfaced as errors for manual review
- **Flag:** `--write-fixed` enables corrected export copy; errors in non-fixable fields preserved intentionally
- **Decision merged:** Export Validator Fix Scope (2026-04-29)
- **Status:** Completed; ready for merge review

## 2026-05-05T19:49:26Z: Mixed-sign Spending Regression Fix (Background)

- **Task:** Fix backend regression where validation rejected balanced mixed-sign creditor amounts
- **Diagnosis:** `normalizeSpendingTransactions` and `isBalancedTransaction` in `src/Backend.elm` were incorrectly stripping non-zero negative amounts from individual transaction lines
- **Fix:** Preserve signed amounts through normalization; only drop rows that sum to exactly zero after merging by (date, secondaryDescription) bucket
- **Deliverables:**
  - Modified `src/Backend.elm` to keep non-zero signed transaction lines
  - Added regression test in `tests/BackendTests.elm` with mixed-sign scenario (total 100, creditors [200, -100])
- **Validation:** elm-format, check-codecs.sh, both lamdera make targets, npm test, lamdera live HTTP 200
- **Approval:** Vasquez (Tester) reproduced regression, verified fix, and approved for merge
- **Decision merged:** Mixed-sign spending validation (2026-05-05)
- **Status:** Completed; ready for merge
