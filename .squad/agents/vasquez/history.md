# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Group expense and accounting app where shared model changes can break frontend and backend together.
- **Created:** 2026-04-19

## Learnings

- 2026-05-05: The mixed-sign spending regression lives in `src/Backend.elm` validation, not the dialog submit path: `normalizeSpendingTransactions` and `isBalancedTransaction` must preserve non-zero negative amounts so cases like total 100 with creditors `200` and `-100` survive, and `tests/BackendTests.elm` now guards that exact backend seam.
- 2026-04-28: Regression coverage in `tests/BackendTests.elm` now replays active transactions to compare exact stored `totalGroupCredits` snapshots against recomputation at global/year/month/day scope; current failures show `src/Backend.elm` edit/delete flows leave zero-valued group entries and empty period buckets behind after `removeTransactionFromModel`, while `groupTransactionForList` and `spendingTransactionsForDetails` still correctly expose only the active replacement rows.
- 2026-04-27: Review of the backend cleanup + group-ordering pass confirmed `src/Backend.elm` still needs `PendingTransaction` because it carries staging-only `year`/`month`/`day` fields into `assignTransactionIds` and the year/month/day storage buckets, while stored `Transaction` records no longer persist those fields; `getSpendingTransactions` is gone, but `src/Frontend.elm` now reverses a backend `RequestGroupTransactions` list that is already produced newest-first via nested `Dict.foldr`, and the added frontend test only proves a synthetic `List.reverse` helper instead of the real backend/frontend ordering seam.

- 2026-04-27: Dallas's follow-up revision restores `Spending.transactionIds` in `src/Types.elm` and `src/Codecs.elm`, and `src/Backend.elm` now recovers a spending's transactions through that stored id list plus `findTransaction` instead of `allTransactionsWithIds model |> List.filter`; validation passed with codec check, both Lamdera builds, `npm test`, and an HTTP 200 probe on the already-running local server.

- 2026-04-27: Reviewing the current transaction-identity refactor showed the repo state still removes `Spending.transactionIds` from `src/Types.elm`/`src/Codecs.elm` and recovers spending transactions by `allTransactionsWithIds model |> List.filter (\( _, transaction ) -> transaction.spendingId == spendingId)` in `src/Backend.elm`; tests/compiles can pass while this requirement still regresses.

- 2026-04-26: Widened the compact per-line field to 200px to ensure full ISO date visibility in transaction details (branch: squad/review/vasquez-fix-date-width).

- Initial roster assignment: Tester and reviewer for risky cross-cutting changes.
- 2026-04-22: Final UI review for PR #39 / commit `ae26ce6` confirmed the fix belongs in `normalizeSpendingDialogLines` in `src/Frontend.elm`: passive row normalization must not seed opposite-side amounts, while compact row alignment needs width constraints on the outer labeled blocks, not just the inner controls.
- 2026-04-21: Hicks's spending editor follow-up polish in `src/Frontend.elm` keeps the approved contract intact while restoring labeled group fields (`Debitor 1` / `Creditor 1`), using inline SVG icon controls, and rendering revealed per-line details as Description before Date.
- 2026-04-21: The ready-row/auto-grow/collapse seam is enforced by `normalizeSpendingDialogLines` and `normalizeTransactionLines` in `src/Frontend.elm`, which prune blank extras and keep one trailing placeholder row per debitor/creditor list.
- 2026-04-22: PR #39 / commit `5eab7a5` keeps the editor contract intact while splitting spending-total edits onto `normalizeSpendingDialogTotal` so total changes stop re-autofilling line amounts, and reuses `transactionLineFlexibleFieldWidth` plus `transactionLineCompactFieldWidth` to keep primary/detail rows on the same width contract across breakpoints in `src/Frontend.elm`.

- 2026-04-28: Test failure investigation identified `getSpendingTransactionsWithIds` filtering out non-Active transactions. Filter removed to include all statuses. All 15 elm tests passing after fix.

- 2026-04-28: Evergreen work is now explicitly authorized, and the workspace already contains untracked auto-generated `src/Evergreen/V26/` plus `src/Evergreen/Migrate/V26.elm` from a `lamdera check --force` pass. The migration surface is still the big V24 → V26 model jump (singleton transaction dialog/history to spending+transaction split), and `src/Evergreen/Migrate/V26.elm` currently carries 39 `Unimplemented` placeholders, so review must treat the first commit as pure generated artifacts and the follow-up commit as all semantic migration logic.

- 2026-04-28: Reviewer focus for Evergreen in this repo is the persistence seam, not compile success: `src/Evergreen/V24/Types.elm` still stores per-day `Day.spendings : List Spending`, transaction-addressed dialogs/messages, and no top-level `BackendModel.spendings`, while `src/Evergreen/V26/Types.elm` / `src/Types.elm` expect append-only `BackendModel.spendings : Array Spending`, `Day.transactions : Array Transaction`, `Spending.transactionIds`, `SpendingReference`, and spending-scoped dialogs/messages.

- 2026-04-28: Current validation baseline is green before any manual migration edits: `lamdera --version` = `0.19.1`, `npm test` passes (15 tests), `./check-codecs.sh` passes, and both `lamdera make src/Frontend.elm --output=/dev/null` and `lamdera make src/Backend.elm --output=/dev/null` succeed. Key reviewer file paths for this migration window are `src/Evergreen/Migrate/V26.elm`, `src/Evergreen/V24/Types.elm`, `src/Evergreen/V26/Types.elm`, `src/Types.elm`, `src/Backend.elm`, and `tests/{BackendTests,CodecsTests,FrontendTests}.elm`.
 
- 2026-04-28: Hudson's `scripts/compare_exports.py` proves storage-level parity (`logical_spendings`, totals, integrity warnings), but it does **not** reconstruct the production `RequestGroupTransactions` seam in `src/Backend.elm`; reviewer coverage for group listings still needs a direct per-group active-transaction derivation or endpoint-level regression because `groupTransactionForList` owns active filtering, credit/debit share sign, and description stitching. Validation on this review pass: `lamdera --version` = `0.19.1`, both `lamdera make` targets succeed, and `npm test` passes (27 tests).

## Core Context

**Spending/Transaction Model (Phase 2 Contract):**
- Spending is the edited unit; transactions are immutable line items
- Spending-level invariant enforced in backend: `total credits = total debits = spending.total`
- Each transaction line owns its own (year, month, day) and optional secondaryDescription
- Spending date used only as UI default seed for new lines
- SpendingTransaction remains ID-free in wire format; backend assigns TransactionId after insertion
- Codec parity check (`./check-codecs.sh`) required alongside compile health as release gate
- No Evergreen migration generated; deferred pending user model review

**Spending Dialog Contract (UI Refinement):**
- Ready first row + one auto-growing trailing placeholder row per debitor/creditor list
- Empty extra rows collapse when fully cleared
- Compact icon-only controls: ▸/▾ for details toggle, × for remove
- Row labels are inline group fields (`Debitor 1`, `Creditor 1`, etc.)
- Details (Date + Description) hidden by default; auto-reveal when secondary description non-empty OR line date differs from spending date
- Details render Description before Date when revealed
- Debitors render before creditors
- Desktop: one flexible field + one 150px compact field
- Small screens: paired fields split available width evenly
- Spending total edits treated as parent-level changes; do not auto-fill debit/credit line amounts
- Outer `el` wrapper owns width contract; inner Input/DatePicker use `width fill` for alignment reliability

**Validation gates (all passing):**
- `elm-format --validate src/` ✅
- `./check-codecs.sh` ✅
- `lamdera make src/Frontend.elm --output=/dev/null` ✅
- `lamdera make src/Backend.elm --output=/dev/null` ✅
- `lamdera live` → HTTP 200 ✅

**Key files:**
- `src/Types.elm`: SpendingTransaction (ID-free), Spending (with total), Transaction (dated, optional secondary description)
- `src/Backend.elm`: validateSpendingTransactions (spending-level invariant only)
- `src/Frontend.elm`: normalizeSpendingDialogLines, normalizeTransactionLinesWithoutAutofill, transactionLineDetailsVisible, addSpendingInputs, width layout contracts

## Summarized Context (2026-04-22 through 2026-04-27T12:14)

**UI Seam & Validation Evolution:**
- 2026-04-22T17:04:59Z: Final UI fixes approved (PR #39). Both regression fixes confirmed: normalizeTransactionLinesWithoutAutofill prevents opposite-side seeding, outer `el` width contract aligns date/field blocks.
- Elm test harness initialized with `elm-test init --compiler "$(which lamdera)"` and integrated into CI. Suite covers transaction invariants, dialog logic, codec parity (13 tests, all passing).
- Validator gate requirement locked: `elm-format --validate src/` + `./check-codecs.sh` required as release checks alongside compile health.
- No Evergreen migration files generated throughout Phase 2 (deferred pending user model review).

**Backend/Model Refactor Rejection Cycle:**
- **Cycle 1 (Bishop, 2026-04-27T11:47:00Z):** Incomplete Evergreen migration (`src/Evergreen/Migrate/V26.elm` contains Unimplemented placeholders). Rejected; Bishop locked out.
- **Cycle 2 (Newt, 2026-04-27T12:04:51Z):** Append-only positional-transaction logic internally correct and validation passes, but removes persisted codec shapes (`BackendModel.nextSpendingId`, `Spending.transactionIds`, `Transaction.id`) without migration support. Under no-migration rule, rejected; Newt locked out.
- **Cycle 3 (Dallas, 2026-04-27T12:16:40Z):** Same backend logic coherence, validation still passes, but persisted codec shapes still changed without authorized migration. Rejected under no-migration constraint; Dallas locked out.
- **Recovery (Hudson, 2026-04-27T12:17:00Z):** Fixed same-day drift by appending in `addTransactionToDay`, preserved persisted shapes (all IDs remain), validation passed, compatibility safe. **APPROVED.** Session deemed complete.

**Clarified Direction (2026-04-27T13:18:29Z):**
- User directive: Codec compatibility no longer required; codecs just match new model. Evergreen generation still deferred until explicit user request.
- Impact: Enables stripped refactor (Array storage, no persisted IDs) without legacycompatibility layer.

**New Approval (2026-04-27T13:38:00Z):**
- Dallas array refactor under clarified rule: `BackendModel.spendings : Array Spending`, `Day.transactions : Array Transaction`, all persisted IDs removed, codecs regenerated (no legacy fields), `src/Backend.elm` appends with `Array.push` and derives IDs from array position, membership via `transaction.spendingId`. Evergreen untouched. Validation: formatting, codecs, both `lamdera make`, `npm test` (13/13), HTTP 200. **APPROVED.**

### 2026-04-22T17:04:59Z: Final UI Seam Fixes Approved

- Reviewed Hicks commit `ae26ce6` on `squad-model-change` / PR #39 for final UI seam fixes
- Confirmed both fixes present:
  1. Row editing no longer seeds opposite-side amounts via `normalizeTransactionLinesWithoutAutofill`
  2. Date/field block width now matches amount/field block width via outer `el` width contract
- Full regression sweep verified: ready first row, trailing placeholder, empty-row collapse, icon controls, debitors-before-creditors, inline labels, hidden details by default, description-before-date, spending-level invariant, line-level ownership all intact
- **Team outcome:** All regressions passed; PR #39 approved and ready for merge

## Learnings

[Summarized into Summarized Context above.]

## Summarized Context (2026-04-27 through 2026-04-28)

**Refactoring & Validation Cycle (2026-04-27):**
- Accepted test harness with 13 elm-test cases; integrated into CI with npm test runner
- Rejected Hudson's `Spending.transactionIds` restoration (model/codec incomplete) but approved Dallas's corrected implementation with proper codec alignment and `findTransaction` lookup
- Approved Dallas's array refactor under clarified codec compatibility rule
- Rejected ordering implementation (synthetic test coverage insufficient), approved Hicks's revision with realistic seam testing and same-day ordering proof
- Fixed `getSpendingTransactionsWithIds` status filter regression; now returns all transaction statuses for audit trail visibility
- Established validator principle: repo state must align with directives; gate success alone insufficient

**Migration & Safety Testing (2026-04-28):**
- Reviewed Evergreen V24→V26 migration artifacts; approved for production with clean commit boundaries and no `Unimplemented` placeholders
- Expanded migration test coverage: backend fixtures assert reconstructed spendings, per-day transactions, membership, status propagation, and totals; frontend tests require stale-ID safety (reset/no-op for dialog state)
- Reviewed group-listing diff export seam: approved Dallas's revision for coverage of active filtering, credit/debit sign rendering, description composition, and ordering semantics
- Implemented 3 comprehensive backend regression tests confirming aggregate replay invariant; isolated defect to `removeTransactionFromModel`
- Total replay test failures provide specification for backend remediation

**Key Learnings:**
- Test suite does not catch missing model properties; validator diligence requires workspace alignment verification
- Migration safety evidence must include user-facing seams, not just storage parity
- Transaction status visibility critical for edit/delete audit trails and slot reuse prevention

## 2026-05-05T19:49:26Z: Mixed-sign Spending Regression Verification (Background)

- **Task:** Verify and review Bishop's fix for mixed-sign creditor spending regression
- **Reproduction:** Manually confirmed regression in live app: spending dialog rejects balanced mixed-sign creditor amounts with validation error "Spending total must match total credits and total debits"
- **Bishop's Fix Review:** Examined changes to `src/Backend.elm` validation and `tests/BackendTests.elm` regression test
- **Verification Scope:** Approved scenario: total 100 with creditors [200, -100] must succeed after fix
- **Validation:**
  - Reproduced original failure on reverted backend
  - Verified fix resolves the regression on restored backend
  - Confirmed all validation gates: elm-format, check-codecs.sh, both lamdera make targets, npm test, lamdera live HTTP 200
- **Verdict:** ✓ Approved for merge
- **Decision merged:** Mixed-sign spending validation (2026-05-05)
- **Status:** Completed
