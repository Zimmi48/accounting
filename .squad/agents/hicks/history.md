# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Group expense and accounting app with Elm frontend and shared domain types.
- **Created:** 2026-04-19

## Core Context

**Most Recent:** Transaction ordering fix (2026-04-27) — Frontend now correctly reverses backend's oldest-first listing to newest-first display.

**Frontend responsibilities:**
- Spending editor UI (src/Frontend.elm): debitors before creditors, auto-growing rows, no prominent Add button, row normalization with blank pruning
- Row width contract: outer `el` owns width assignments, inner controls use `width fill` for breakpoint consistency
- Transaction listing: consumes backend's `RequestGroupTransactions` (oldest-first via nested Dict.foldr), reverses to newest-first with same-day index ordering (later indexes sort ahead)
- Ordering semantics: Backend order is ascending keys → frontend reversal maintains UI newest-first invariant

**Key learnings:**
- Backend `allTransactionsWithIds` emits oldest-first (ascending key order from Dict.foldr)
- Frontend consumer seam (`groupTransactionsFromBackend`) applies List.reverse to store newest-first
- Test coverage requires realistic backend response (ascending), not synthetic data
- Row normalization must not auto-fill opposite-side amounts during editor edits
- Detail-date column needs 200px minimum width for full ISO date visibility

**Approval chain:**
- UI Editor Polish (2026-04-21): ✅ Approved
- Final UI Seam Fixes (2026-04-22, PR #39): ✅ Approved  
- Virtual Transaction Line Alignment (2026-04-27): ✅ Approved
- Transaction Ordering Revision (2026-04-27): ✅ Approved by Vasquez

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

## Learnings

- 2026-05-05: Negative spending totals are still a supported signed-total flow in this app. The regression was a frontend submit guard in `src/Frontend.elm` (`canSubmitSpending`) introduced during the multi-date spending refactor; backend validation in `src/Backend.elm` needed the same non-zero signed-total rule to keep create/edit behavior aligned. Relevant skill note updated in `.squad/skills/spending-validation/SKILL.md`.

- 2026-04-26T10:38:28Z: Implemented safe per-line-date behavior so line.date remains Nothing until user sets it; dateText still shows the dialog default. Verified detail-date column width. Branch: squad/review/hicks-fix-date-defaults. Draft PR: https://github.com/Zimmi48/accounting/pull/43

- 2026-04-26T14:31:25Z: Spawned to investigate and fix DatePicker.init misuse per directive: .squad/decisions/inbox/copilot-directive-2026-04-26T14-31-25Z.md. See orchestration log: .squad/orchestration-log/2026-04-26T14-31-25Z-hicks.md

- 2026-04-26T14:45:00Z: Replaced incorrect uses of DatePicker.initWithToday with initialization + DatePicker.setVisibleMonth and added a dialog-local `today : Maybe Date` field to the spending dialog model so pickers can receive the real "today" value. Local `lamdera make` failed due to dependency resolution; decision filed in .squad/decisions/inbox/hicks-fix-datepicker.md. Branch: squad/hicks/fix-datepicker-visible-month

- 2026-04-26T15:22:38Z: Team clarification from Théo: "do not add tests until I ask for this." Confirms the implementation approach is correct and no test additions are required until user request. See .squad/orchestration-log/2026-04-26T15:22:38Z-hicks.md and .squad/decisions.md (merged inbox).

- 2026-04-26T15:39:00Z: Date-picker follow-up in `src/Frontend.elm`: line detail pickers should render the spending-level default (including today) as the selected date even when `line.date` stays `Nothing`, while the main spending picker should explicitly close on `DatePicker.DateChanged`. Validated with `elm-format`, both `lamdera make` targets, and `lamdera live` returning HTTP 200.

### 2026-04-26T15:35:00Z: Date-picker bugs complete

- Completed final date-picker fixes in `src/Frontend.elm`:
  1. Line date pickers now display spending-level default as selected value even when `line.date = Nothing` (visual confirmation without changing data model)
  2. Main spending date picker closes immediately after user selects a date
  3. Calendar now correctly shows today's date and defaults to intended spending/line date as selected
- **Validation:** elm-format ✅, lamdera make Frontend/Backend ✅, lamdera live HTTP 200 ✅
- **Status:** All three reported bugs resolved; ready for review and merge
- **User request addressed:** Line pickers show default selected, today's date visible, main picker closes on select

- 2026-04-27T09:22:00Z: Spending dialog line editors in `src/Frontend.elm` no longer persist a trailing blank debitor/creditor row in `AddSpendingDialogModel`; `transactionLineInputs` now renders that extra row virtually and seeds real rows through `AddDebit`/`AddCredit` carrying an initial `TransactionLine` from the view. Validated with `elm-format src/ --yes`, `lamdera make src/Frontend.elm`, `lamdera make src/Backend.elm`, and `lamdera live --port=8002` serving HTTP 200.

### 2026-04-27T09:14:31Z: Virtual Empty Line Completion

- Completed refactor to move trailing empty transaction line from model state to view layer:
  - `normalizeTransactionLines` now prunes all blank rows instead of maintaining one trailing placeholder
  - `transactionLineInputs` callback (addMsg) changed to accept an initial `TransactionLine` argument
  - Virtual trailing empty row rendered by view when appropriate
  - Row creation triggered through `AddDebit`/`AddCredit` messages with initial line data from view
  - Progressive-entry UX preserved: users see extra empty row, model only contains meaningful data
- **Validation:** elm-format ✅, lamdera make Frontend/Backend ✅, lamdera live HTTP 200 ✅
- **Status:** Model decoupled from UI placeholders; ready for integration
- **Decision:** Merged to .squad/decisions.md as "Virtual Empty Transaction Line (2026-04-27)"

### 2026-04-27T09:37:26Z: Virtual Line Alignment with listInputs

- Refined virtual transaction-line callback semantics per user feedback:
  - `transactionLineInputs` callback (addMsg) now accepts group name only instead of full `TransactionLine`
  - Amount auto-filled on line creation, preserving suggested split UX from previous version
  - Aligns with `listInputs` pattern: virtual row is view-only, creation via single-argument callback
- **Validation:** elm-format ✅, lamdera make Frontend/Backend ✅, lamdera live HTTP 200 ✅
- **Status:** Alignment complete; ready for review
- **Decision:** Merged to .squad/decisions.md as "Virtual Transaction Line Alignment (2026-04-27)"

- 2026-04-27T10:18:00Z: Spending dialog virtual-row follow-up in `src/Frontend.elm`/`src/Types.elm`: trailing debitor/creditor row now appears exactly while every current row has a non-empty group name, model cleanup helpers were reduced to blank-row pruning (no normalization pass), and add messages were renamed to `AddDebitor` / `AddCreditor` to match domain terms. Validated with `elm-format src/ --yes`, `lamdera make src/Frontend.elm`, `lamdera make src/Backend.elm`, and `lamdera live --port=8002` returning HTTP 200.

- 2026-04-27T16:02:33Z (Vasquez rejection & reassignment): Hudson's `reverse-transaction-order` revision rejected. Root issue: backend `allTransactionsWithIds` produces ascending (oldest-first) order via nested `Dict.foldr`; Hudson incorrectly claimed "already newest-first" and removed frontend reversal, regressing display to oldest-first. Test remains synthetic: feeds fake newest-first to trivial pass-through, never validates real seam. **Hicks assigned as next owner.** Tasks: (1) restore consumer-side reversal in `ListGroupTransactions` handler, (2) rewrite test with realistic ascending backend response, (3) assert stored result is newest-first. Files: `src/Frontend.elm`, `tests/FrontendTests.elm`.

- 2026-04-27T16:08:00Z: Restored the `ListGroupTransactions` consumer-side `List.reverse` in `src/Frontend.elm` so frontend state stays newest-first when backend responses arrive oldest-first. Replaced the weak ordering check in `tests/FrontendTests.elm` with a seam-focused regression that feeds an ascending backend-style payload (including same-day index ordering) and asserts the stored result is reversed. Validated with `elm-format src/Frontend.elm tests/FrontendTests.elm --yes`, `lamdera make src/Frontend.elm --output=/dev/null`, `lamdera make src/Backend.elm --output=/dev/null`, `npm test`, and `lamdera live --port=8002` returning HTTP 200.

### 2026-04-27T16:22:00Z: Transaction Ordering Revision — APPROVED ✅

- **Verdict:** Vasquez approved Hicks's ordering revision without further revision needed.

**What was verified:**
- ✅ Frontend reversal restored at `groupTransactionsFromBackend` consumer seam in `src/Frontend.elm`
- ✅ Backend `allTransactionsWithIds` confirmed still emits oldest-first via nested `Dict.foldr` pattern (lowest keys first)
- ✅ Test regression upgraded: realistic ascending backend response → newest-first consumption + same-day index ordering coverage (Apr 18 idx=2 before idx=1)
- ✅ All 15 elm tests pass (2 new ordering + 13 prior tests intact)
- ✅ Group isolation case covered
- ✅ Validation gates: elm-format, both lamdera make targets, npm test, HTTP 200

**Status:** Artifact resolved. Ready for merge.

**Orchestration:** Vasquez review completed 2026-04-27T16:22:00Z. Decision recorded in `.squad/decisions/decisions.md`. Orchestration log: `.squad/orchestration-log/20260427-161057-vasquez-review-hicks-ordering.md`.

- 2026-05-05T20:35:59Z: Fixed negative total spending regression by updating `canSubmitSpending` guard in `src/Frontend.elm` to allow non-zero signed totals (`totalInt /= 0` instead of `totalInt > 0`), updated matching backend validation in `src/Backend.elm`, and updated `.squad/skills/spending-validation/SKILL.md` with corrected semantics. Frontend and backend now both treat spendings as valid when credits, debits, and total all match the same non-zero amount (positive or negative), while preserving zero-total invalidity. Vasquez approved for team archive. Validation: elm-format, check-codecs, both lamdera make targets, npm test (33/33), HTTP 200. Orchestration log: `.squad/orchestration-log/2026-05-05T20:35:59Z-hicks.md`. Decision merged: `.squad/decisions/decisions.md`.
