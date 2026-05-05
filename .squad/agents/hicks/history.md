# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Group expense and accounting app with Elm frontend and shared domain types.
- **Created:** 2026-04-19

## Core Context

**Most Recent:** Negative total spending fix (2026-05-05) — Frontend and backend now support signed-total spendings (positive or negative with non-zero magnitude).

**Frontend responsibilities:**
- Spending editor UI (src/Frontend.elm): debitors before creditors, auto-growing rows, no prominent Add button, row normalization with blank pruning
- Row width contract: outer `el` owns width assignments, inner controls use `width fill` for breakpoint consistency
- Transaction listing: consumes backend's `RequestGroupTransactions` (oldest-first via nested Dict.foldr), reverses to newest-first with same-day index ordering (later indexes sort ahead)
- Ordering semantics: Backend order is ascending keys → frontend reversal maintains UI newest-first invariant
- Spending validation: `canSubmitSpending` allows non-zero signed totals while maintaining invariant `credits == debits == total`

**Key learnings:**
- Backend `allTransactionsWithIds` emits oldest-first (ascending key order from Dict.foldr)
- Frontend consumer seam (`groupTransactionsFromBackend`) applies List.reverse to store newest-first
- Test coverage requires realistic backend response (ascending), not synthetic data
- Row normalization must not auto-fill opposite-side amounts during editor edits
- Detail-date column needs 200px minimum width for full ISO date visibility
- Negative spendings require both frontend and backend agreement on validation semantics (cross-cutting seam)

**Approval chain:**
- UI Editor Polish (2026-04-21): ✅ Approved
- Final UI Seam Fixes (2026-04-22, PR #39): ✅ Approved  
- Virtual Transaction Line Alignment (2026-04-27): ✅ Approved
- Transaction Ordering Revision (2026-04-27): ✅ Approved by Vasquez
- Negative Total Spending Fix (2026-05-05): ✅ Approved by Vasquez

## Early Work Summary (2026-04-19 to 2026-04-27)

**2026-04-19:** Initial spending/transaction split UI implementation. Spending editor UI added per-line transaction date and secondary description fields while keeping creditor/debitor entry layout. Frontend submit path groups line items into `SpendingTransaction` buckets by `(date, secondaryDescription)` and requires each bucket to stay balanced. Shared/backend touchpoints in `src/Types.elm`, `src/Backend.elm`, `src/Codecs.elm`, and Evergreen migration snapshots.

**2026-04-21:** Spending editor polish in `src/Frontend.elm`: debitors render before creditors, each row shows group/amount first, date plus secondary description collapsed by default. Added inline SVG icon controls for detail toggle and row removal (evaluated `agj/elm-simple-icons` but chose local SVG to avoid brand-logo dependency). Approved by Vasquez.

**2026-04-22:** Final UI fixes for normalizeSpendingDialogLines (prevent opposite-side autofill) and row width alignment (outer `el` owns width, inner controls use `width fill` for both primary and detail fields). Spending-total edits treated as parent-level changes.

**2026-04-24:** Stabilized Msg case ordering in `src/Frontend.elm` to reduce noisy diffs (moved UpdatePassword, UpdateJson, ViewportChanged, ToggleTheme to canonical positions).

**2026-04-26:** Date-picker refinements: line .date stays Nothing until user explicitly changes it; when spending date changes, update only dateText/datePickerModel for lines without explicit dates (avoid silent overrides). Increased detail-date column to 200px for full ISO visibility.

**2026-04-27:** Virtual transaction line refactor—trailing empty row moved from model to view layer. Transaction line callbacks now accept group name only with auto-filled amount. Added messages renamed to `AddDebitor`/`AddCreditor` to match domain terms. Fixed transaction ordering regression: restored consumer-side `List.reverse` in `groupTransactionsFromBackend` to maintain newest-first invariant when backend emits oldest-first. Upgraded test coverage with realistic ascending backend response and same-day index ordering proof.

## Recent Approvals & Fixes

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
