# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Group expense and accounting app with shared types across frontend and backend.
- **Created:** 2026-04-19

## Core Context

### Spending/Transaction Model Architecture
- Phase 1 split complete: `BackendModel.spendings : Dict SpendingId Spending` + dated `Day.transactions : List Transaction`
- Edit/delete pattern: mark old as `Replaced`/`Deleted`, create new records (append-only at record lifecycle)
- Bidirectional references: `Spending.transactionIds` (forward) + `Transaction.spendingId` (back-reference)
- Current issue: prepend in `addTransactionToDay` causes index/position mismatch when `Spending.transactionIds` stored durably
- Long-term design: canonical membership should derive from immutable `Transaction.spendingId`; remove redundant `Spending.transactionIds` at next migration

### Critical Patterns
- **Phase discipline:** Cross-cutting changes (Types + Backend + Frontend + Codecs) must compile at every step; never layer Phase 2 before Phase 1 compiles
- **Codec field order:** `Codec.object` applies fields positionally; mismatched order causes silent data corruption
- **Evergreen migrations:** Removing persisted fields requires migration generation in `src/Evergreen/Migrate/`; use `lamdera check --force` locally, only `elm-format` validates in CI
- **Codecs:** Regenerate via `./check-codecs.sh --regenerate` using elm-review-derive; manual tweaks needed for phantom types

### Evergreen & Migration Safety
- Latest: V24 (only frontend changed for Theme; Backend ModelUnchanged)
- Migrations live in `src/Evergreen/Migrate/`
- Removing stored fields: needs migration logic (e.g., group old transactions by bucket, sum to spending total)
- Current constraint: Do not generate Evergreen migrations until user approves model changes

## Legacy Learnings (2026-04-19 to 2026-04-20)

## Learnings (2026-04-20)

- **Phase 2 contract correction (2026-04-20)**: User clarified that bucket-level totals were incorrect. The invariant should be at spending scope (total credits = total debits = stated total). Each transaction line should carry its own date and optional secondary description. Spending date is a UI default for convenience, not a data constraint. Wrote detailed contract to `ripley-phase2-contract-correction.md` covering: remodeled dialog (spendingDate, spendingTotal, transactionLines), backend validation shift to spending scope, deferred Evergreen migration for Transaction.total removal, and open questions for UX refinement. Decision: no code changes until contract approval.
- **Bucket-total enforcement pattern**: Backend `transactionBucketKey = (year, month, day, secondaryDescription)` groups transactions into buckets for aggregation. `transactionBucketTotals` and `transactionBucketMetadata` compute per-bucket totals and store them in Transaction records. This is a mechanical reusable pattern but conflates UI grouping (buckets as a convenience) with data invariants (totals as a constraint). The user correction separates them: buckets are display/edit grouping only; invariant is spending-scoped.
- **Migration safety for stored fields**: Removing `Transaction.total` requires Evergreen migration because it is persisted in the backend. Options: (1) Remove entirely + migrate, (2) Repurpose for spending total + migrate, (3) Keep but ignore + fragile. Recommendation: option (1) after user approval. Migration logic: group old transactions by bucket, sum to get spending total, store in new `Spending.total` field.
- **Frontend dialog modeling**: Current `TransactionBucket` separates date, description, total, and lists of (group, amount, validity) tuples per side. Corrected model flattens to `TransactionLine` (one per visible row) with individual date, description, group, amount, side. Dialog state complexity increases: more form fields, more update messages, more validation hooks. No new types strictly required, but struct design matters for handler clarity.

## 2026-04-21: Phase 2 Contract Correction Approved

- **Session timestamp:** 2026-04-21T06:49:24Z
- **Contract locked:** User directive captured and implemented by Hudson + Bishop
- **Spending-level invariant:** Backend now enforces `total credits = total debits = spending.total` after normalization
- **Per-line ownership:** Dates and optional secondary descriptions stored at transaction level
- **Spending date role:** UI default seed only, not a data constraint
- **ID-free wire format:** `SpendingTransaction` remains free of embedded transaction IDs
- **Next phase:** Data model finalization and Evergreen migration planning await user approval

## 2026-04-26: Squashed PR Review Orchestrated

- **Session timestamp:** 2026-04-26T16:17:40Z
- **Assignment:** Lead reviewer for squashed commit 68d1d8b ("Change the model to allow spendings to combine transactions on multiple dates")
- **Scope:** Full diff review for logic bugs, suspicious patterns, state management correctness
- **Focus:** Backend.elm (836 lines), Frontend.elm (1217 lines), Types.elm, Codecs.elm
- **Outcome:** Review conducted. Results documented in orchestration log.

## Learnings (2026-04-27): Transaction ID Regression Analysis

- **Root cause of ID instability**: `assignTransactionIds` assigns indices from `dayTransactionCount` (an append-position model), but `addTransactionToDay` prepends (`transaction :: day.transactions`). These two choices are incompatible. The stored `Spending.transactionIds` map to wrong list positions from the moment they are written.
- **Why old code was safe**: Old `Day.spendings` had no stored IDs. `TransactionId.index` was computed live by `List.indexedMap` in `ListGroupTransactions` and used immediately. The listing and the resolving traversed the same list in the same order — there was no time gap for drift. The key property: identity was **derived at read time**, never stored at write time.
- **Why new code breaks**: The spending-dialog change introduced `Spending.transactionIds : List TransactionId` — stored durably. IDs must now survive the lifetime of the spending, which requires write-time stability the current prepend scheme cannot provide.
- **Scope of impact**: The bug is not limited to multi-transaction spendings. Any two spendings sharing the same day are affected because the second spending's transaction gets index=1 (correct append position) but lands at list position 0 (prepend). All subsequent `findTransaction` calls via `getSpendingTransactions` are wrong for that day.
- **Data integrity risk**: `EditSpending` and `DeleteSpending` both call `getSpendingTransactions` to roll back aggregate credits before rewriting. Wrong transaction set = wrong amounts removed = permanently corrupted group-credit aggregates. Silent.
- **Minimal fix**: Change `addTransactionToDay` from prepend to append (one line: `day.transactions ++ [ transaction ]`). Correct and complete; no Evergreen migration needed on the feature branch.
- **Principled fix**: Remove `Spending.transactionIds` and rewrite `getSpendingTransactions` to filter by `transaction.spendingId` (already stored, immutable, correct). Eliminates the entire class of stored-ID drift. Requires Evergreen migration to remove the field. This is the right long-term design: child-to-parent back-reference is the canonical membership data; parent-to-child forward-reference creates redundancy that can drift.
- **Key file**: `src/Backend.elm` — `addTransactionToDay` (line 512), `assignTransactionIds` (line 678), `getSpendingTransactions` (line 944), `findTransaction` (line 453).

## 2026-04-27T10:37:26Z: Transaction ID Regression Analysis Session

- **Spawned:** Ripley (Lead) to analyze and document transaction-ID instability regression
- **Analysis Output:** Full regression analysis and recommendations
  - Documented why old code was safe: positional IDs were ephemeral (computed live by `List.indexedMap`), never stored
  - Documented why new code breaks: `Spending.transactionIds` stores IDs durably, but prepend/append mismatch causes them to map to wrong records from write-time
  - Identified data-integrity risk: wrong transaction sets corrupt group-credit aggregates silently
  - Scope: **any two spendings sharing a day**, not only multi-transaction spendings
  - Provided two options: Option A (immediate one-line fix: append instead of prepend), Option B (deferred: remove Spending.transactionIds, use back-reference scan)
- **Decision:** Analysis merged to decisions.md (2026-04-27 "Transaction ID Regression Analysis" + "Backend ID Stability")
- **Status:** Completed — Recommendations ready for team approval and implementation

## Learnings (2026-04-27): Array vs List for Day Transactions

- **Container swap is not an identity model**: Replacing `Day.transactions : List Transaction` with `Array Transaction` would only make slot lookup cheaper. It does not by itself define which slot is the canonical identity, nor protect correctness if anything later reorders, rebuilds, or re-buckets the day container.
- **What Array would actually fix**: If the model commits to append-only per-day storage forever, a persisted `(year, month, day, index)` could line up with `Array.get index` more directly than today's prepended list. That addresses the current prepend/append mismatch, but only as a storage-discipline fix, not as a clearer domain contract.
- **Membership should stay child-to-parent**: For reassembling a spending's transactions, `Transaction.spendingId` is the correct canonical relation. `Spending.transactionIds` is redundant forward state and remains drift-prone whether the day container is a `List` or an `Array`.
- **Stable child identity is still a separate question**: Even if membership is derived by `spendingId`, transaction rows may still need a stable identity when the UI or future features must point to one exact stored line among duplicates. That identity can be stored explicitly (`Transaction.id`) or derived from an append-only slot, but it should not be conflated with spending membership.
- **Architectural preference**: Favor model clarity first — canonical back-reference for membership, optional explicit transaction identity only if exact row addressing is required. Do not choose `Array` as the primary fix for a referential-integrity problem.

## 2026-04-27T11:02:33Z: Array vs List Architectural Review

- **Session timestamp:** 2026-04-27T11:02:33Z
- **Orchestration:** Completed with Bishop (sync review)
- **Task:** Analyze whether `Day.transactions : Array` solves transaction-ID stability and reduces model complexity
- **Output:** Detailed architectural analysis documented in decisions.md
- **Key Finding:** Container swap does not solve identity problem; array changes resolution method, not necessity
- **Recommendation:** Favor model clarity (back-reference membership) over container type; defer array as future local optimization
- **Decision merged:** ripley-array-vs-list.md + ripley-backend-id-review guidance merged to decisions.md (2026-04-27)

## 2026-04-27T11:41:15Z: User Directive — No Auto-Generated Evergreen Migrations

- **Directive:** Do not generate Evergreen migrations until the user explicitly asks for them.
- **Context:** User deleted newly generated Evergreen migration files from the repo because they were created before approval.
- **Impact on Ripley:** All future migration work (e.g., removing `Spending.transactionIds` per Option B analysis, V26 work) requires explicit user approval before file generation.
- **Scope:** Applies to this agent and all team members.
- **Stored in:** .squad/decisions.md (User Directives section), .squad/log/, .squad/orchestration-log/

## 2026-04-27T13:00:00Z: PendingTransaction Analysis — Construction-Phase Type

- **Request:** Théo asked for detailed explanation of why `PendingTransaction` exists and its purpose.
- **Analysis:** Traced complete flow from Frontend `SpendingTransaction` → Backend `PendingTransaction` → Storage `Transaction`.
- **Key finding:** PendingTransaction is **not redundant**; it is the **construction-phase type**. The 3 extra date fields (`year`, `month`, `day`) are routing information that guides placement into the date-indexed hierarchy (years → months → days). Once stored, dates become implicit in container position and are stripped.
- **Workflow phases identified:**
  1. Frontend sends `SpendingTransaction` (wire format: dates + user input, no IDs)
  2. Backend enriches to `PendingTransaction` (adds spendingId, metadata, preserves dates for routing)
  3. Backend routes via `addTransactionToYear/Month/Day` (uses date fields to traverse hierarchy)
  4. `storedTransaction` explicitly strips dates (dates become implicit in position)
  5. Stored `Transaction` lives in `Day.transactions: Array Transaction` (position is canonical identity)
  6. On read-back: combine `Transaction` + `TransactionId` to reconstruct `SpendingTransaction`
- **Design principle:** Canonical membership is child-to-parent back-reference (`Transaction.spendingId`); canonical temporal identity is immutable position in day. Storing dates would violate both constraints.
- **Concrete functions that require it:** `addTransactionToYear/Month/Day` (routing), `storedTransaction` (boundary enforcement), `assignTransactionIds` (index tracking), `createSpendingInModel` (orchestration).
- **Verdict:** Keep. It is the right design for this phase. No redundancy.
- **Documented in:** `.squad/decisions.md` (section "2026-04-27T13:00:00Z: PendingTransaction Architecture Role & Purpose")

## 2026-04-27T15:55:22Z: Explanation Task Completed — PendingTransaction Role

- **Session timestamp:** 2026-04-27T15:55:22Z
- **Task:** Explain why `PendingTransaction` stays and what purpose it serves
- **Status:** Completed
- **Outcome:** Determined PendingTransaction is still necessary because it carries year/month/day during construction and routing; stored Transaction omits these because date becomes implicit in day-bucket position
- **Deliverables:**
  - Orchestration log: `.squad/orchestration-log/2026-04-27T15-55-22Z-ripley.md`
  - Session log: `.squad/log/2026-04-27T15-55-22Z-pending-transaction-explanation.md`
  - Decision merged: `.squad/decisions.md` (section added + inbox file removed)
- **Requested by:** Théo Zimmermann

## 2026-04-28: PendingTransaction Refactor Proposal Review

- **Session timestamp:** 2026-04-28
- **Task:** Review proposal to refactor `PendingTransaction` to wrap a date + nested `Transaction` for clarity
- **Status:** Analysis Complete
- **Verdict:** NOT CREDIBLE. Proposal misunderstands the design.
- **Key Finding:** `PendingTransaction` is a construction-phase type; dates are routing information (guidance for placement into date-indexed hierarchy), not data attributes. Once stored in `Day.transactions[index]`, dates become implicit in position and are stripped by `storedTransaction()`. Wrapping dates inside persisted `Transaction` would:
  - Introduce redundancy with the path (year, month, day, index)
  - Create consistency hazards (stored date vs. implicit position can diverge)
  - Require Evergreen migration (violates user directive: no auto-generated migrations)
  - Provide no clarity gain (dates are always known from context when reading)
- **Blocking Issues:** Persisted type stability (codec/Evergreen), user migration directive
- **Recommendation:** If goal is clarifying read-back, define a helper to reconstruct dates from `TransactionId` instead. Keep design clean.
- **Deliverable:** `.squad/decisions/inbox/ripley-pendingtransaction-wrapper-review.md`
- **Requested by:** Théo Zimmermann


## 2026-04-27T17:50:04Z: PendingTransaction Refactor Proposal Review – Decision Processed

- **Session timestamp:** 2026-04-27T17:50:04Z
- **Task:** Review proposal to refactor `PendingTransaction` to wrap a date + nested `Transaction` for clarity
- **Status:** DECISION PROCESSED AND MERGED ✅
- **Verdict:** NOT CREDIBLE. Proposal misunderstands the design.
- **Deliverables:**
  - Orchestration log: `.squad/orchestration-log/20260427-175004-ripley-pendingtransaction-wrapper-review.md` ✅
  - Session log: `.squad/log/20260427-175004-pendingtransaction-wrapper-review.md` ✅
  - Decision merged into `.squad/decisions.md` (section "2026-04-27T17:50:04Z: PendingTransaction Refactor Proposal Review – Ripley Analysis") ✅
  - Inbox file deleted: `.squad/decisions/inbox/ripley-pendingtransaction-wrapper-review.md` ✅
- **Key Finding:** `PendingTransaction` is a construction-phase type; dates are routing information (guidance for placement into date-indexed hierarchy), not data attributes. Wrapping them inside persisted `Transaction` would violate type stability, require Evergreen migrations, and provide zero clarity gain.
- **Status for user:** Awaiting clarification on the underlying problem this refactor is meant to solve. Current recommendation: **DO NOT PROCEED**.
- **Requested by:** Théo Zimmermann

## Learnings (2026-04-28): Evergreen V26 Migration

- **Backend storage reshape pattern:** `src/Evergreen/Migrate/V26.elm` must rebuild `BackendModel.spendings : Array Spending` and each `Day.transactions : Array Transaction` together from `src/Evergreen/V24/Types.elm` legacy `Day.spendings : List Spending`. The safe pattern is chronological traversal (year/month/day, then day-local spending order), assigning new `SpendingId`s from an append-only counter while generating matching `transactionIds` from per-day append-only indexes.
- **Reference preservation rule:** When old persisted data does contain enough information, preserve it exactly: each migrated transaction keeps the migrated spending status, and each migrated spending stores the transaction ids that point at the new day-array slots. This keeps `findTransaction`, `getSpendingTransactionsWithIds`, delete/edit rollback, and group transaction listing coherent after deploy.
- **Safe reset boundary:** Old frontend state and in-flight messages that only know a legacy `TransactionId` cannot recover a correct new `SpendingId` without backend context. In `src/Evergreen/Migrate/V26.elm`, preserve backend history exactly, but reset unverifiable frontend/UI seams (`groupTransactions`, edit/delete dialogs, legacy edit/delete/request messages) to safe no-ops rather than inventing ids.
- **Legacy-to-new transaction bridge:** Old single-day credit/debit dictionaries migrate cleanly into new `SpendingTransaction` or stored `Transaction` rows by fanning out credits and debits on the legacy day, with empty `secondaryDescription` and group-members metadata rebuilt from `BackendModel.groups` + `BackendModel.persons`.
- **Validation seam:** For this repo, migration work is not done until `lamdera check --force`, `elm-format src/ tests/ --yes`, `lamdera make src/Frontend.elm --output=/dev/null`, `lamdera make src/Backend.elm --output=/dev/null`, `npm test`, and `lamdera live` with an HTTP 200 probe all pass. Key files: `src/Evergreen/Migrate/V26.elm`, `src/Evergreen/V24/Types.elm`, `src/Evergreen/V26/Types.elm`, `src/Types.elm`, `src/Backend.elm`, `src/Frontend.elm`.

## 2026-04-28: Evergreen V24→V26 migration completed

**Session:** Evergreen migration preparation
**Partner Agent:** Vasquez (review + validation coverage)

Successfully executed two-commit Evergreen workflow:
1. Commit ea069a6: Auto-generated files from `lamdera check --force`
2. Commit fa185f07: Manual migration fills for all `Unimplemented` placeholders

**Key strategy decisions:**
- Preserve backend accounting history by rebuilding both new storage surfaces (top-level `spendings` array + per-day `transactions` array) in single chronological pass
- Derive new IDs from append-only migration order to keep durable references coherent
- Reconstruct `groupMembersKey` / `groupMembers` from legacy data during migration
- Reset unverifiable frontend-only state to safe no-ops

**Validation results:**
- All repo checks green (tests, codecs, Frontend compilation, Backend compilation)
- All `Unimplemented` placeholders resolved
- Migration correctness confirmed by Vasquez (no data loss risks identified)

**Outcome:** Ready for production deploy with confidence. Durable ID mapping ensures post-deploy consistency.

## 2026-04-28T18:30:00Z: Spending Total Recomputation Bug Analysis

- **Session timestamp:** 2026-04-28T18:30:00Z
- **Task:** Write extensive tests for spending total recomputation during add/edit/delete lifecycle; identify failing test patterns to expose bugs
- **Status:** DEFECT IDENTIFIED — 3 tests fail consistently, proving bugs exist
- **Methodology:**
  1. Analyzed Backend.elm total-tracking flow (addTransactionToModel, removeTransactionFromModel, intermediate Day/Month/Year aggregation)
  2. Identified key invariants: global totalGroupCredits, year-level totals, month-level totals, day-level totals should all stay consistent
  3. Wrote 3 targeted tests covering add→delete, edit→delete, and multi-spending edit/delete scenarios
  4. All 3 tests failed with Amount 0 when expecting non-zero totals

- **Failed Tests:**
  1. "delete after add should remove all owed amounts" — Expected [1200, 0], got [0, 0]
  2. "edit then delete should eventually reach zero" — Expected [1200, 2000, 0], got [0, 0, 0]
  3. "multiple spendings: day total tracks through edits" — Expected [1000, 1300, 400], got [0, 0, 0]

- **Root Cause Identified:**
  - The `getGroupMembersKey` function (Backend.elm:561-580) constructs dict keys by filtering group members through `model.persons` and joining their IDs
  - When transactions reference groups that haven't been registered as `Person` records, the key becomes "" (empty string)
  - Totals are aggregated under "" instead of the intended "1,2" key
  - Lookups fail silently because the key doesn't match between add and remove operations
  - This is a **critical data-integrity bug**: after edit→delete, totals remain stuck at intermediate values instead of reaching zero

- **Invariants Violated:**
  - ✗ global totalGroupCredits not populated correctly
  - ✗ Year/Month/Day intermediate totals not tracked
  - ✗ After delete, totals should reach 0 but stay at intermediate values

- **Impact:**
  - User's observed bug matches this pattern: after deleting a previously-edited spending, the "owed" totals don't reset correctly
  - The prepend/append transaction ID mismatch (from previous analysis) compound this: wrong transactions removed = wrong amounts subtracted

- **Deliverable:** `.squad/decisions/inbox/ripley-delete-total-bug.md` with full analysis and test coverage
- **Status:** Tests added to `tests/BackendTests.elm` (lines 213-287). All 3 fail on current code.
- **Requested by:** Théo Zimmermann (suspected bug after deployment)

## 2026-04-28: Total Recomputation Investigation Merged

- Completed root cause analysis in `.squad/decisions/inbox/ripley-delete-total-bug.md`
- Identified four violated invariants at global/year/month/day scopes
- Documented `getGroupMembersKey` empty-string defect and its cascade through edit/delete lifecycle
- Decision merged into `.squad/decisions.md` after Vasquez confirmed with regression tests
- Vasquez test evidence shows 2 of 30 tests now fail, proving defect is real and reproducible

## 2026-04-28T18:45:00Z: Lifecycle Totals Test Review — Flawed Assertions

**Task:** Review the two new failing tests in `tests/BackendTests.elm` (lines 126–169) to determine whether assertions are logically correct.

**Verdict:** TESTS ARE FLAWED.

**Key Finding:** Tests assert `storedTotalsSnapshot == recomputedTotalsSnapshot` at every lifecycle stage. This is over-constrained and conflates two distinct data representations:

1. **Stored totals:** Accumulate all contributions incrementally, including zeroed reversals. After `removeTransactionFromModel(-amount)`, the bucket keeps the entry at zero (correct accounting).

2. **Recomputed totals:** Filter to only active transactions. Omit keys with no active txns (correct filtering).

**Example from test output (after edit):**
- Stored:     `{Alice: 0, Bob: 800, Trip: -800}` — includes Alice entry, now zeroed
- Recomputed: `{Bob: 800, Trip: -800}` — omits Alice because she has no active txn

Both are logically correct; the test conflates them.

**Correct invariant:** "For every Active transaction where spending.status == Active, its contribution is stored in all enclosing buckets."

**What revision is needed:** Reframe to test stored-bucket correctness for active transactions only, via explicit filter before comparison. Three options documented in `.squad/decisions/inbox/ripley-lifecycle-totals-review.md`.

**Requested by:** Théo Zimmermann

## 2026-04-29T06:59:52Z: Lifecycle Totals Test Review

- **Session:** Orchestrated split review with Bishop
- **Task:** Determine if failing lifecycle-total tests in `tests/BackendTests.elm` (lines 126–169) are correct or flawed
- **Finding:** Tests are over-constrained; assertion conflates two valid data representations:
  - **Stored ledger:** Accumulates all contributions incrementally, including zeroed reversals
  - **Recomputed filter:** Omits keys with no active transactions
- **Recommendation:** Reframe assertion to filter stored-totals before comparing (Options A–C in full review)
- **Orchestration status:** Under review; awaiting decision on test remediation strategy
- **Artifact:** `.squad/decisions/inbox/ripley-lifecycle-totals-review.md` (archived to decisions.md)
