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

- 2026-05-15: `src/Backend.elm:editSpendingInModel` now reconciles normalized edited rows against active stored rows by logical row identity `(date, secondaryDescription, group, side, amount)`, reassigning matched rows to the replacement spending and only marking unmatched rows `Replaced`; regression coverage lives in `tests/BackendTests.elm`.
- 2026-05-15: `src/Backend.elm:groupTransactionPageItems` must emit a `GroupTransactionYearSummary` for each visible year when a paged response spans multiple years, even if the oldest visible year is still partial overall; regression proof lives in `tests/BackendTests.elm` with the page-2 2025→2024 seam merged through `Frontend.groupTransactionsFromBackend`.
- 2026-05-16: `src/Backend.elm:groupTransactionPageItems` must also emit the leading year summary when a load-more page starts in a newly visible older year, even if that page stays within one year and does not yet reach that year's final month; regression coverage lives in `tests/BackendTests.elm` on the 2026-01 → 2025-12/11 seam.
- 2026-05-15: Evergreen V34 migrates the flat group-transaction frontend seam by resetting cached `FrontendModel.groupTransactions` and pagination metadata, translating legacy `RequestGroupTransactions String` to `{ group, before = Nothing, pages = 1 }`, and dropping stale flat `ListGroupTransactions` plus edit-only `ShowAddSpendingDialog (Just _)`; regression coverage lives in `tests/MigrationTests.elm`.
- 2026-05-16: Evergreen V35 is a `FrontendMsg`-only transaction-list migration for month folding and viewport rechecks. `src/Evergreen/Migrate/V35.elm` should keep every V34 constructor unchanged and needs no frontend-model reset because persisted state shape stays the same; proof lives in `tests/MigrationTests.elm`.

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

## Summarized Context (2026-04-27 through 2026-04-29)

**ID Stability & Schema Tradeoffs (2026-04-27):**
- Evaluated Array vs List backend tradeoff for transaction storage; recommended stored-ID approach for current model complexity
- Designed append-only positional transaction ID scheme to stabilize indices without schema migration
- Attempted removal of stored `Transaction.id` and `Spending.transactionIds` for append-only model (rejected by Vasquez due to codec breaking change)
- Investigated delete/edit performance: confirmed `setSpendingStatus` called once per operation; redundant traversal in `setTransactionStatuses` + `removeTransactionFromModel` is architectural not accidental; optimization deferred pending profiling evidence

**Lifecycle Totals Bug Discovery & Remediation (2026-04-28 to 2026-04-29):**
- Identified real backend data corruption: `removeTransactionFromModel` leaves zero-valued entries in `totalGroupCredits` dicts at all scopes plus stale entries in `Person.belongsTo` set
- Impact partially hidden by UI filters (`RequestUserGroups` filters non-zero credits/debits); fragile—proper fix requires source cleanup
- User directive: track cleanup as non-priority follow-up, preserve test coverage without pinning leak as contract
- Implemented export validator tooling (`scripts/validate_totals.py`) to replay active transactions and recompute derived fields (`totalGroupCredits`, `belongsTo`) for validation/repair; safe to rewrite only derived fields, must surface errors in non-fixable integrity issues for manual review

**Key Learnings:**
- Append-only positional indexing can stabilize transaction IDs but requires strict discipline everywhere
- Schema shape change cost exceeds local optimization benefit for current model scope
- Test failures reveal real bugs; validator must check workspace alignment against directives, not just gate success

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

## 2026-05-15T08:04:13Z: Spending Edit Preservation Fix (Background)

- **Task:** Fix issue #49 — preserve unchanged spending rows during edit operations
- **Problem:** Backend spending edit flow marked every prior transaction `Replaced` and appended a fully fresh spending, even when rows were logically unchanged. This hid stable history and violated the intent of stable row preservation.
- **Root Cause:** `updateSpending` handler in `src/Backend.elm` lacked logical row identity matching; replaced all rows regardless of content changes
- **Solution:** Implement reconciliation by logical row identity `(date, secondaryDescription, group, side, amount)` before replacing:
  - Keep matched rows active; update their `spendingId` to attach to replacement spending
  - Refresh preserved rows with new spending-wide metadata (`groupMembersKey`, `groupMembers`)
  - Mark only unmatched old rows `Replaced`; append only unmatched new rows
- **Deliverables:**
  - Backend reconciliation logic in `src/Backend.elm`
  - Test coverage in `tests/BackendTests.elm` verifying preservation
  - Skill documentation: `.squad/skills/spending-edit-preservation/SKILL.md`
- **Validation:** elm-format, lamdera make src/Frontend.elm, lamdera make src/Backend.elm, npm test, lamdera live HTTP 200
- **Status:** ✅ Completed; commit 8edf105 approved for merge
- **Decision merged:** Spending edit transaction preservation (2026-05-15)

### 2026-05-15T16:43:52Z: Late-Arriving Year Header Seam — COMPLETED ✅

- **Task:** Fix the seam where an older year first appears on page 2 without rendering its year header line.
- **Root Cause:** Paginated group transaction list could introduce an older year on page 2 without emitting the corresponding year summary header.
- **Solution:** Emit year summary for each visible year when a response spans multiple years:
  - Backend carries year totals on every month slice
  - Emits year header whenever page spans multiple years or reaches visible end of year
  - Frontend merge already hoists late-arriving headers (no frontend changes needed)
- **Deliverables:**
  - Backend emission logic in `src/Backend.elm`
  - Test regression in `tests/BackendTests.elm` covering exact page-2 2025→2024 shape
- **Validation:** elm-format ✅, lamdera make src/Frontend.elm ✅, lamdera make src/Backend.elm ✅, npm test ✅, lamdera live HTTP 200 ✅
- **Status:** ✅ Completed; commit d5f7f8a approved and ready for merge
- **Reviewer:** Vasquez approved
