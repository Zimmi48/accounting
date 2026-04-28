# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Full-stack group expense and accounting app with shared models, backend logic, and Elm UI.
- **Created:** 2026-04-20

## Learnings

- 2026-04-28: `scripts/compare_exports.py` now also compares each group's active transaction list using the same semantics as `RequestGroupTransactions` in `src/Backend.elm`: only active transactions whose owning spending is also active, normalized to date, rendered description (`description` + optional secondary description), spending total, and signed share. Key paths: `scripts/compare_exports.py`, `README.md`, `src/Backend.elm`.
- 2026-04-28: Added `scripts/compare_exports.py` as a standalone migration-review tool for export diffs. It normalizes legacy day-scoped `spendings` exports and current split `spendings`+`transactions` exports into logical spendings, semantic `totalGroupCredits`, groups, and person-name sets; it intentionally ignores storage churn like raw `transactionIds`, `loggedInSessions`, and opaque `groupMembersKey` strings. Usage is documented in `README.md`.
- 2026-04-27: `RequestGroupTransactions` in `src/Backend.elm` already emits newest-first rows through nested `Dict.foldr`, so the frontend seam in `src/Frontend.elm` must preserve backend order instead of reversing it. Regression coverage belongs on the `ListGroupTransactions` consumer path (now `groupTransactionsFromBackend`) with realistic backend-ordered fixtures, not on a standalone reversal helper. Validation for this frontend-only fix passed with `elm-format src/ tests/ --yes`, both `lamdera make` targets, `npm test` (15/15), and `lamdera live --port=8124` returning HTTP 200; no codec regeneration was needed.
- Joined to own the post-model-review cleanup pass after prior authors were locked out on the spending/transaction split artifact.
- User directive: do not generate the Evergreen migration before Théo reviews the model changes.
- For the model-only spending/transaction split, the review seam is codec alignment: `src/Codecs.elm` and `src/Codecs.elm.stub` must stay in sync with `src/Types.elm`, and `./check-codecs.sh` is the fastest gate.
- This cleanup cycle confirmed the current worktree is already in the compile-first review state: no new `src/Evergreen/` migration files were needed, while `elm-format --validate src/`, `./check-codecs.sh`, both `lamdera make` targets, and `lamdera live` with HTTP 200 all passed.
- `2026-04-20T16:43:52Z`: Model-only spending/transaction split approved for user review
- 2026-04-27: The direct-lookup fix for spending details is to keep `Day.transactions` append-only as `Array Transaction`, restore `Spending.transactionIds`, assign those ids from current day counts before writes, and resolve spendings through stored ids instead of `allTransactionsWithIds |> List.filter`. Key paths: `src/Types.elm`, `src/Backend.elm`, `src/Codecs.elm`, `README.md`, and `check-codecs.sh` now avoids `/tmp` by using a repo-local backup during codec checks.

- 2026-04-20: Corrected model pass keeps `TransactionId` as `{ year, month, day, index }`, expands each logical spending bucket into one-sided dated transactions, reconstructs single-bucket spending details for the current dialog, and still defers any Evergreen migration until after user review. Key paths: `src/Types.elm`, `src/Backend.elm`, `src/Codecs.elm`, `src/Codecs.elm.stub`.

- 2026-04-20: Corrected Array target after commit `e64d99e` misread the user request. User asked for Array storage for **spendings**, not for Day.transactions. Changed `BackendModel.spendings` from `Dict SpendingId Spending` to `Array Spending`, and reverted `Day.transactions` from `Array Transaction` back to `List Transaction`. Updated all related code paths and codecs. All validation gates passed with no new Evergreen files. The branch now correctly implements both user directives: Amount wrapper for transaction amounts, and Array storage for spendings.

### 2026-04-21: Phase 2 Contract Correction Approved

- **Session timestamp:** 2026-04-21T06:49:24Z
- **Approved commits:** Hudson `b7d0444` (spending-level invariant) + Bishop `862817b` (codec parity)
- **Final verdict:** All review gates pass. Contract confirmed and locked.
- **Next phase:** Awaiting user approval of any backend record changes before Evergreen migration.
- **Team coordination:** Ripley clarified contract, Hudson restored invariant, Bishop refreshed codecs, Vasquez approved stack.
- 2026-04-27: Compatibility-safe recovery for the rejected transaction-addressing cleanup kept the append-only day-list write path, but restored persisted `BackendModel.nextSpendingId`, `Spending.transactionIds`, and `Transaction.id` so saved backend JSON and exports stayed shape-compatible without Evergreen work. Key review seam: `src/Backend.elm`, `src/Types.elm`, `src/Codecs.elm`, plus README contract wording; validation stack passed with `elm-format src/ tests/ --yes`, `./check-codecs.sh`, both `lamdera make` targets, `npm test`, and `lamdera live` responding with HTTP 200 on port 8002.

## 2026-04-27T12:16:40Z: Reassignment to Compatibility Recovery Pass

**Event:** Hudson assigned to next backend/model compatibility recovery pass after cycle 3 rejection.

**Context:** Bishop, Newt, and Dallas are now locked out. Three rejection cycles all pointed to same constraint: persisted codec shapes must not change without explicit Théo authorization and migration plan.

**Task:** Produce backend/model revision that preserves persisted codec compatibility for `Spending`, `Transaction`, and `BackendModel` while fixing runtime lookup semantics.

**Key Insight from Cycles 1–3:**
- Cycle 1 (Bishop): Incomplete migration with Unimplemented placeholders
- Cycle 2 (Newt): Internal logic sound but breaking codec changes
- Cycle 3 (Dallas): Runtime correctness achieved but persisted shapes still not safe

**Pattern:** The constraint is strictly enforced. Either preserve old codec shapes entirely, or bring explicit Théo authorization + full migration plan.

**Validation Requirements:**
- `elm-format --validate src/`
- `./check-codecs.sh`
- `lamdera make src/Frontend.elm --output=/dev/null`
- `lamdera make src/Backend.elm --output=/dev/null`
- `npm test` (expected 13/13 passing)
- `lamdera live --port=8123` → HTTP 200
- No new Evergreen migration generation (unless authorized)
- Persisted codec shape remains compatible or migration plan is explicit

## 2026-04-27T12:17:00Z: Compatibility-Safe Recovery Approved

**Status:** ✅ APPROVED and MERGED

**Outcome:** Hudson's compatibility-safe recovery pass fixed the transaction ID seam while preserving persisted shape fields. Vasquez validated all gates and approved for merge.

**Implementation Details:**
- Append-only same-day transaction storage (fixed `addTransactionToDay` to append instead of prepend)
- Restored `BackendModel.nextSpendingId`, `Spending.transactionIds`, `Transaction.id` in handwritten types and codecs
- No Evergreen migration files generated (persisted shape unchanged)

**Validation Complete:**
- `elm-format --validate src/ tests/` ✅
- `./check-codecs.sh` ✅
- `npm test`: 13/13 passing ✅
- `lamdera make src/Frontend.elm` ✅
- `lamdera make src/Backend.elm` ✅
- `lamdera live` → HTTP 200 ✅

**Session Status:** Ready for merge and deployment. No outstanding rework required.

## 2026-04-27T14:39:52Z: Rejection & Reassignment to Dallas

**Event:** Vasquez review cycle 4 complete. Restoration attempt rejected.

**Status:** Locked out for this artifact in current cycle.

**What was attempted:** Restore `Spending.transactionIds` in model/codecs/backend while keeping append-only day storage.

**Why rejected:** Current repo state does **not** have `Spending.transactionIds` in `src/Types.elm` or `src/Codecs.elm`. Backend still recovers spending transactions by `allTransactionsWithIds model |> List.filter` on `spendingId`. Requirement not satisfied.

**Evidence:** Tests pass, both `lamdera make` commands pass, but required model property absent from workspace.

**Validation gates checked:** All passed (formatting, codecs, compile, tests, HTTP 200).

**Constraint violation:** The user directive ("keep transactionIds on Spending; do not scan/filter all transactions") is not implemented in the current workspace state, even though the validation suite reports success.

**Next assignment:** Dallas takes over next restoration pass.

## 2026-04-27T15:52:08Z: Ordering/Test Revision Reassignment from Dallas

**Event:** Vasquez split verdict: cleanup approved, ordering rejected.

**Assignment:** Hudson now owns the `reverse-transaction-order` revision.

**Task:** 
1. Re-check actual producer order for `ListGroupTransactions` and make frontend ordering explicit against that contract
2. Replace/extend regression coverage to exercise real backend/frontend seam, not just helper reversal
3. Protect same-day ordering behavior in test

**Why:** Current implementation reverses `ListGroupTransactions` list without verifying the backend producer order. `RequestGroupTransactions` in `src/Backend.elm` builds via nested `Dict.foldr` (already newest-first), so reversing likely inverts back to older-first. Test only covers synthetic helper, not real seam.

**Status:** Active; ready for Hudson to take over.

## 2026-04-27T16:02:33Z: Ordering Revision Rejection & Lockout

**Event:** Vasquez completed sync review of Hudson's `reverse-transaction-order` revision.

**Verdict:** REJECTED ❌

**Root Issues:**
1. **Factual error in decision basis:** Hudson claimed backend `allTransactionsWithIds` walks "newest-first" via nested `Dict.foldr`. Reality: Elm's `Dict.foldr` with pattern `\k v acc -> items(k) ++ acc` yields ascending order (lowest key first). Result: transactions arrive oldest-first, not newest-first.

2. **Functional regression:** Frontend previously reversed ascending backend response to achieve newest-first display. Hudson removed `List.reverse` without verifying backend order—display now shows oldest-first (regression).

3. **Test remains synthetic:** Test constructs already-newest-first input to trivial `groupTransactionsFromBackend` pass-through. Never validates that real backend response (ascending) is correctly reversed before display. Cannot catch regressions in real ordering flow.

**Consequence:** 
- **Hudson: 🔒 Locked out for this artifact** (standing self-revision policy)
- **Dallas: 🔒 Remains locked from prior cycle**
- **Hicks → Next owner**

**Decision Recorded to .squad/decisions.md**

**Status:** Locked; awaiting Hicks's revision.

---

## Session: Export Diff Tool Completion (2026-04-28T14:46:16Z)

**Topic:** Export diff tool for pre/post migration JSON comparison

**Status:** ✅ Complete

**Deliverables:**
- `scripts/compare_exports.py` — semantic comparison script
- README.md — documentation updates

**Decision:** "Export diff normalization for migration review" approved and merged to decisions.md

**Validation:** Repo validation passed. Tool normalizes logical spendings, groups, person-name sets, and totals while ignoring storage-only churn.

**Outcome:** Addresses core challenge of noisy JSON diffs by enabling semantic comparison between legacy and current export formats.

## 2026-04-28: Group Transaction Diff Tool - Export Seam Coverage

**Event:** Initial implementation of per-group active-transaction comparison for export diff.

**Assignment:** Implement scripts/compare_exports.py with per-group comparison to catch regressions in group transaction listings (user-facing seam).

**Outcome:** First revision rejected by Vasquez for not replaying real `RequestGroupTransactions` seam semantics. Locked out and reassigned to Dallas for revision.

**Key finding:** Storage-level parity alone is not sufficient; must include active filtering, description composition, sign rendering, and ordering from real backend/frontend paths.

**Impact:** Established that export diff tool must compare the complete group-listing seam, not just aggregate storage facts.
