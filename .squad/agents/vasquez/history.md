# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Group expense and accounting app where shared model changes can break frontend and backend together.
- **Created:** 2026-04-19

## Recent Learnings

- 2026-05-05: Negative spending totals are still part of the product contract. The submit seam in `src/Frontend.elm` and the backend invariant in `src/Backend.elm` must both treat `spending.total /= 0` as valid when credits and debits match the same signed total, and regressions now live in `tests/FrontendTests.elm` plus `tests/BackendTests.elm`.
- 2026-05-05: The mixed-sign spending regression lives in `src/Backend.elm` validation, not the dialog submit path: `normalizeSpendingTransactions` and `isBalancedTransaction` must preserve non-zero negative amounts so cases like total 100 with creditors `200` and `-100` survive, and `tests/BackendTests.elm` now guards that exact backend seam.

## Core Context

**Spending/Transaction Model (Phase 2 Contract):**
- Spending is the edited unit; transactions are immutable line items
- Spending-level invariant enforced in backend: `total credits = total debits = spending.total`
- Each transaction line owns its own (year, month, day) and optional secondaryDescription
- Spending date used only as UI default seed for new lines
- SpendingTransaction remains ID-free in wire format; backend assigns TransactionId after insertion
- Codec parity check (`./check-codecs.sh`) required alongside compile health as release gate
- Validator: Negative spendings require both frontend and backend agreement on validation logic (cross-cutting seam)

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
- `src/Backend.elm`: validateSpendingTransactions (spending-level invariant only), isBalancedTransaction (signed-total logic)
- `src/Frontend.elm`: normalizeSpendingDialogLines, canSubmitSpending, width layout contracts
- `tests/FrontendTests.elm`, `tests/BackendTests.elm`: Regression coverage for negative spendings

## Early Work Summary (2026-04-19 to 2026-04-28)

**2026-04-21–04-22:** Spending editor UI polish approved (PR #39). Fixed two critical seams: normalizeSpendingDialogLines no longer seeds opposite-side amounts, and row width contract moved to outer `el` for alignment reliability. Elm test harness initialized with `elm-test init --compiler "$(which lamdera)"` (13 tests, all passing).

**2026-04-22–04-26:** Various regression fixes tracked: UI seam validation, Evergreen migration review (V24→V26 model jump from singleton dialog/history to spending+transaction split), backend cleanup validation. Date-picker refinement: compact field widened to 200px for ISO date visibility. Transaction-identity refactor under review: backend recovery via `findTransaction` vs filter pattern.

**2026-04-27:** Review of transaction ordering pass confirmed backend `PendingTransaction` necessity (carries staging-only year/month/day fields), and frontend `RequestGroupTransactions` ordering semantics verified (backend emits oldest-first via nested Dict.foldr, frontend reverses to newest-first).

**2026-04-28:** Regression test coverage expanded: backend replay test validates stored `totalGroupCredits` snapshots at global/year/month/day scope, identified defect in `removeTransactionFromModel`. Evergreen migration artifacts authorized for production. Status filter removed from `getSpendingTransactionsWithIds` to include all statuses for audit trail visibility.

## Recent Approvals & Decisions

**UI Seam & Validation Evolution:**
- 2026-04-22T17:04:59Z: Final UI fixes approved (PR #39). Both regression fixes confirmed: normalizeTransactionLinesWithoutAutofill prevents opposite-side seeding, outer `el` width contract aligns date/field blocks.
- Elm test harness initialized with `elm-test init --compiler "$(which lamdera)"` and integrated into CI. Suite covers transaction invariants, dialog logic, codec parity (13 tests, all passing).
- Validator gate requirement locked: `elm-format --validate src/` + `./check-codecs.sh` required as release checks alongside compile health.

**Backend/Model Refactor Cycle & Approvals:**
- Multiple revision cycles in late 2026-04-27 evaluated codec compatibility, persistence semantics, and migration safety
- Final array refactor approved (2026-04-27T13:38:00Z): `BackendModel.spendings : Array Spending`, `Day.transactions : Array Transaction`, all persisted IDs removed
- Dallas's transaction identity refactor approved with proper codec regeneration
- Hudson's transaction ordering revision approved with realistic seam testing (frontend reversal confirmed necessary)

### 2026-04-22T17:04:59Z: Final UI Seam Fixes Approved

- Reviewed Hicks commit `ae26ce6` on `squad-model-change` / PR #39 for final UI seam fixes
- Confirmed both fixes present:
  1. Row editing no longer seeds opposite-side amounts via `normalizeTransactionLinesWithoutAutofill`
  2. Date/field block width now matches amount/field block width via outer `el` width contract
- Full regression sweep verified: ready first row, trailing placeholder, empty-row collapse, icon controls, debitors-before-creditors, inline labels, hidden details by default, description-before-date, spending-level invariant, line-level ownership all intact
- **Team outcome:** All regressions passed; PR #39 approved and ready for merge

### 2026-05-05T19:49:26Z & 2026-05-05T20:35:59Z: Negative Total Spending Fix — APPROVED ✅

- **Task:** Reproduce and fix frontend/backend regression preventing submission of spendings with negative totals
- **Reproduction:** Confirmed frontend `canSubmitSpending` gate rejected balanced dialog with total `-10.00`; backend validation rejected matching `Amount -100` payload
- **Fix Verification:** 
   - Frontend: `canSubmitSpending` allows non-zero signed totals (`totalInt /= 0` instead of `totalInt > 0`)
   - Backend: `isBalancedTransaction` and `validateSpendingTransactions` updated to match
   - Regression coverage added to `tests/FrontendTests.elm` and `tests/BackendTests.elm`
- **Validator focus:** Cross-cutting seam requires frontend/backend agreement; must both enforce signed-total invariant while preserving zero-total invalidity
- **Validation gates:** elm-format ✅, check-codecs ✅, both lamdera make targets ✅, npm test (33/33) ✅, HTTP 200 ✅
- **Status:** Completed and merged to decisions log

