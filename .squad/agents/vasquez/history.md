# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Group expense and accounting app where shared model changes can break frontend and backend together.
- **Created:** 2026-04-19

## Learnings

- 2026-04-26: Widened the compact per-line field to 200px to ensure full ISO date visibility in transaction details (branch: squad/review/vasquez-fix-date-width).

- Initial roster assignment: Tester and reviewer for risky cross-cutting changes.
- 2026-04-22: Final UI review for PR #39 / commit `ae26ce6` confirmed the fix belongs in `normalizeSpendingDialogLines` in `src/Frontend.elm`: passive row normalization must not seed opposite-side amounts, while compact row alignment needs width constraints on the outer labeled blocks, not just the inner controls.
- 2026-04-21: Hicks's spending editor follow-up polish in `src/Frontend.elm` keeps the approved contract intact while restoring labeled group fields (`Debitor 1` / `Creditor 1`), using inline SVG icon controls, and rendering revealed per-line details as Description before Date.
- 2026-04-21: The ready-row/auto-grow/collapse seam is enforced by `normalizeSpendingDialogLines` and `normalizeTransactionLines` in `src/Frontend.elm`, which prune blank extras and keep one trailing placeholder row per debitor/creditor list.
- 2026-04-22: PR #39 / commit `5eab7a5` keeps the editor contract intact while splitting spending-total edits onto `normalizeSpendingDialogTotal` so total changes stop re-autofilling line amounts, and reuses `transactionLineFlexibleFieldWidth` plus `transactionLineCompactFieldWidth` to keep primary/detail rows on the same width contract across breakpoints in `src/Frontend.elm`.

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

### 2026-04-22T17:04:59Z: Final UI Seam Fixes Approved

- Reviewed Hicks commit `ae26ce6` on `squad-model-change` / PR #39 for final UI seam fixes
- Confirmed both fixes present:
  1. Row editing no longer seeds opposite-side amounts via `normalizeTransactionLinesWithoutAutofill`
  2. Date/field block width now matches amount/field block width via outer `el` width contract
- Full regression sweep verified: ready first row, trailing placeholder, empty-row collapse, icon controls, debitors-before-creditors, inline labels, hidden details by default, description-before-date, spending-level invariant, line-level ownership all intact
- **Team outcome:** All regressions passed; PR #39 approved and ready for merge
