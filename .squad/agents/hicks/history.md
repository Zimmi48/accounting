# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Group expense and accounting app with Elm frontend and shared domain types.
- **Created:** 2026-04-19

## Learnings

- 2026-04-24: Stabilized update-case ordering in src/Frontend.elm: moved UpdatePassword, UpdateJson, ViewportChanged to canonical position matching Types.elm to reduce noisy diffs.

- Initial roster assignment: Frontend Elm implementation and UI flow ownership.
- 2026-04-19: Spending/transaction split UI now edits spendings as parents and flattens listed transactions as children; `src/Frontend.elm` adds per-line transaction date and secondary description fields while keeping the existing creditor/debitor entry layout.
- 2026-04-19: The frontend submit path groups line items into `SpendingTransaction` buckets by `(date, secondaryDescription)` and requires each bucket to stay balanced before submit; details come back as grouped transactions and are expanded back into editable lines in `src/Frontend.elm`.
- 2026-04-19: Shared/backend touchpoints for this split live in `src/Types.elm`, `src/Backend.elm`, `src/Codecs.elm`, and the generated `src/Evergreen/V26/` migration snapshot.
- 2026-04-21: The spending editor is lighter again in `src/Frontend.elm`: debitors render before creditors, each row shows group/amount first, and date plus secondary description stay collapsed unless the user reveals them or the row already carries custom detail data relative to the spending date.
- 2026-04-21: `src/Frontend.elm` now keeps the spending editor close to the old inline-row flow by normalizing credit/debit lines to one trailing placeholder row, auto-pruning fully emptied extras, hiding the group label, and using icon-sized detail/remove affordances.
- 2026-04-21: Follow-up polish in `src/Frontend.elm` restored visible per-row group labels (`Debitor 1`, `Creditor 1`, etc.), removed the extra bold row titles, swapped detail-field order to description-then-date, and replaced text glyph controls with small inline SVG stroke icons while keeping the same auto-growing/collapsing line behavior.
- 2026-04-21: `agj/elm-simple-icons` was evaluated for the spending editor, but it is a brand-logo library rather than a general UI-control set, so the dialog kept a local inline-SVG icon helper instead of adding the dependency to `elm.json`.
- 2026-04-22: `src/Frontend.elm` now treats spending-total edits as parent-only changes: debit/credit row amounts keep their current values, while row normalization still preserves the ready trailing placeholder.
- 2026-04-22: Spending dialog row widths now share one breakpoint-aware contract in `src/Frontend.elm`: desktop keeps a flexible main field plus a 150px compact field, while small screens split paired fields evenly for both primary and revealed detail rows.
- 2026-04-22: Final frontend bugfix in `src/Frontend.elm` removed remaining cross-column amount autofill during row normalization, so editing one side no longer seeds the untouched opposite side.
- 2026-04-22: For compact labeled controls in `src/Frontend.elm`, matching block widths are more reliable when the outer `el` owns the width contract and the inner `Input`/`DatePicker.input` simply uses `width fill`.

### 2026-04-21T18:20:11Z: UI Editor Polish Completion

- Completed spending editor refinements in `src/Frontend.elm`:
  - Auto-growing row behavior with ready first row (normalizeTransactionLines)
  - No prominent Add button (rows grow via normalization only)
  - Icon-only affordances: ▸/▾ for details, × for remove
  - Hidden Group label (Input.labelHidden)
  - 'Description' as the shorter label copy
  - Debitors render before creditors (addSpendingInputs order)
  - Empty extra rows collapse when cleared
  - Spending-level invariant + line-level detail contract preserved
- **Validation:** elm-format ✅, lamdera make Frontend/Backend ✅, lamdera live HTTP 200 ✅
- **Status:** Approved by Vasquez; ready for integration

### 2026-04-22T17:04:59Z: Final UI Seam Fixes Completed

- Final bugfix pass in `src/Frontend.elm` commit `ae26ce6` resolved two UI seams:
  1. Row normalization (`normalizeSpendingDialogLines`) no longer auto-fills amounts onto untouched opposite side during debitor/creditor edits
  2. Width layout now shares identical breakpoint-aware contract for both primary and detail rows: outer `el` owns width assignment, inner controls use `width fill`
- **Validation:** elm-format ✅, codecs ✅, both lamdera makes ✅, HTTP 200 ✅
- **Team outcome:** PR #39 approved by Vasquez; ready for merge

- 2026-04-24T17:26:51Z: Diff review: found noisy reorderings (UpdatePassword, UpdateJson, ViewportChanged, ToggleTheme) in src/Frontend.elm. Recommendation: keep Msg case ordering stable; group viewport/config messages together.
- 20260424T173935Z: Restored canonical Msg ordering in src/Frontend.elm: moved ToggleTheme adjacent to viewport/config messages to reduce noisy diffs.

- 2026-04-26: Short fixes applied to spending editor dialog:
  - Keep per-line .date as Nothing until the user explicitly changes it; dateText still reflects the dialog default so the UI shows a sensible date.
  - When the spending date changes, update only line.dateText/datePickerModel for lines that didn't have an explicit date rather than setting line.date — this avoids silently overriding explicit user choices.
  - Increased detail-date compact column width where needed (confirmed at 200px).
  (Frontend-only changes in `src/Frontend.elm` by Hicks)
