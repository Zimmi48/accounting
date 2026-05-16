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

## Learnings

- 2026-05-15: Issue #32's click path already flips `checked` in frontend state (`ToggleTransactionChecked` / `toggleGroupTransactionChecked`) and persists through `ToggleTransactionCheckedRequest`, so the user-visible regression sits in `src/Frontend.elm`'s dot rendering seam rather than backend storage.
- 2026-05-15: The regression escaped because `tests/FrontendTests.elm` only asserted the pure toggle helper and list refresh separately; it never covered the visible checked/unchecked affordance or the composed click-plus-refresh path for the reconciliation dot.
- 2026-05-15: Group transaction chronology now depends on `src/Backend.elm`'s `groupTransactionsForMonth` plus `src/Frontend.elm`'s `normalizeGroupTransactionListItems`; summary-header tests alone do not prove reverse chronology inside a month/day bucket.
- 2026-05-15: For paginated transaction reviews, `tests/BackendTests.elm` must assert actual `GroupTransactionRow` sequence (day and same-day index order), because `groupTransactionBoundaryMarkers` intentionally collapses each month to a single `T YYYY-MM` marker and can hide chronology regressions.
- 2026-05-16: Month-folding review needs explicit seam proof in `tests/FrontendTests.elm`: the selected month header must stay visible while only that month's `GroupTransactionRow`s hide, and later pagination/reload paths must preserve chronology, summary placement, and remembered refresh depth.
- 2026-05-16: At commit `e8e6063`, the month-folding work had not actually landed in `src/Frontend.elm` or `src/Types.elm`—`viewGroupTransactions` still renders every `GroupTransactionListItem` directly and no fold-state message/model/test hook exists—so this review class should reject absent implementation rather than infer intent from pagination-only coverage.
- 2026-05-16: At commit `eb161df`, `src/Frontend.elm` switches month sections to native `<details open>` without any Elm fold state, so a user-collapsed month will reopen on the next rerender (load-more, refresh, transaction check, theme, or viewport update). Tests that only cover `groupTransactionViewSections` and `groupTransactionMonthSectionItems` are therefore helper-only and do not prove the real fold/unfold seam.
- 2026-05-16: Stateful month folding must live in frontend-managed state keyed by `(year, month)` and be exercised through the real update/render path; helper-only section grouping plus native `<details>` markup is not acceptable proof because rerenders recreate the open state.
- 2026-05-16: Commit `522dbe9` fixes the fold seam without shared-type migration by storing a folded month as a duplicated `GroupTransactionMonthSummary` marker inside `FrontendModel.groupTransactions`, then re-deriving fold flags with `groupTransactionViewSections` and reapplying them after normalization in `groupTransactionsFromBackend`; `tests/FrontendTests.elm` now proves rerender and load-more preservation, while the extracted `operationSuccessfulRefreshPlan` test proves refresh-depth replay keeps the folded state alive long enough for the replayed response to reuse it.

- 2026-05-16: Fold-triggered pagination fixes need proof of the real `ToggleGroupTransactionMonthFold -> checkGroupTransactionsViewport -> GroupTransactionsViewportChecked -> requestMoreGroupTransactions` seam; helper-only viewport math tests can pass while the user-visible load-more path remains unproved.
- 2026-05-16: Commit `1d80415` closes that fold-triggered pagination seam acceptably by extracting `toggleGroupTransactionMonthFoldPlan` and `groupTransactionsViewportLoadMorePlan`, then having the `update` branches delegate straight to those helpers; in this repo, plan-level regression proof is strong enough only when production message handling is that thin wrapper and the test still pins the older-history `RequestGroupTransactions { before = Just cursor, pages = 1 }` request.

### 2026-05-15T11:17:55Z: Issue #32 Repair Review — Toggle Dot Visual Affordance ✅ APPROVED

- **Task:** Review Newt's visual repair for transaction toggle dot regression
- **Analysis:** Data flow (click handler, state toggle, backend persistence) already intact from prior #32 decision. Regression isolated to frontend rendering layer: raw embedded SVG with `currentColor` inheritance not reflecting state changes to users.
- **Review Findings:**
  - Regression justified: `tests/FrontendTests.elm` only asserted toggle helpers separately, never the visible affordance or click-plus-refresh composition
  - Repair adequate: elm-ui text glyph replaces SVG; checked/unchecked states render distinctly; composed path preserved in regression tests
  - Validation gates all pass: elm-format, both lamdera make targets, npm test, HTTP 200
- **Verdict:** Approved; commit 9c81ea4 merged
- **Decision merged:** Transaction Toggle Dot Visual Repair (2026-05-15)

- 2026-05-15: Issue #52 revision: top-of-period ordering requires backend page generation logic to hoist year summaries before first loaded month, and frontend merge to normalize late-arriving year summaries above already-visible months (not buried in the middle).
- 2026-05-15: When verifying ordering regressions, boundary markers (Y 2025 → M 2025-04 → T 2025-04-15) must be explicit in test expectations for both initial and load-more paths; implicit "count" assertions miss the ordering requirement.
- 2026-05-15: Mutation-triggered group-transaction reloads need explicit frontend state for "how many pages are already loaded"; reusing `RequestGroupTransactions { before = Nothing }` after add/edit silently collapses deep history back to page 1 even while pagination tests still pass.
- 2026-05-15: When a model change is introduced only to remember pagination depth, the stale generated Evergreen artifacts must be removed, not regenerated, until the user explicitly approves migration work.
- 2026-05-15: Deep-page reload reviews must prove the composed frontend refresh seam, not just helper arithmetic: `src/Frontend.elm` can store `groupTransactionsLoadedPages`, yet the real guard is a test that `OperationSuccessful` re-requests `RequestGroupTransactions` with the remembered depth.
- 2026-05-15: For this pagination contract, chronology/header regression coverage now lives in `tests/FrontendTests.elm` pagination merge expectations plus `tests/BackendTests.elm` page-shape assertions, but those do not substitute for an explicit mutation-refresh test.
- 2026-05-15: The regression proof still fails if `tests/FrontendTests.elm` never exercises `Frontend.updateFromBackend OperationSuccessful`; searching only helper tests (`groupTransactionsReloadPages`, `updatedGroupTransactionsLoadedPages`) is enough to spot the missing seam.
- 2026-05-15: `src/Evergreen/Migrate/V34.elm` and `src/Evergreen/V34/Types.elm` staying deleted is the correct interim state for this model-only pagination fix until the user explicitly asks for migration regeneration.
- 2026-05-15: The acceptable proof pattern for Lamdera mutation refreshes is to extract a pure helper like `Frontend.operationSuccessfulRefreshPlan`, have `updateFromBackend OperationSuccessful` consume it directly, and test the replayed `RequestGroupTransactions` plus the refreshed merged list together.
- 2026-05-15: For the deep-page reload seam, the explicit composed proof now lives in `tests/BackendTests.elm` because it can drive backend page generation, frontend refresh planning, and frontend list merging in one regression without trying to unwrap Lamdera `Cmd`s.
- 2026-05-15: V34 remains intentionally unregenerated for this review-first workflow: no `src/Evergreen/Migrate/V34.elm` or `src/Evergreen/V34/Types.elm` file should reappear before the user asks for migration work.
- 2026-05-15: The late-year pagination bug lives in `src/Backend.elm`'s page slicing seam: `groupTransactionMonthSlices` attaches a year summary only to the oldest month in that year, so `takeTransactionMonthSlices` can load the first months of a newly entered older year on page 2 without its year header if that year itself still spans more than 100 transaction rows.
- 2026-05-15: Existing pagination tests are too soft for this seam. `tests/BackendTests.elm` only proves later-page year summaries when the page also includes the summary-carrying boundary month, and `tests/FrontendTests.elm` only hoists a late summary within the same year; neither proves "new year first appears on page 2 and must already show its summary line."

### 2026-05-15T15:40:58Z: Issue #52 Summary Header Ordering — APPROVED ✅

- **Task:** Implement issue #52 revision where summary rows appear as headers leading their periods (previously requested fix for summary row positioning)
- **Implementation:**
  - Backend `src/Backend.elm`: Month summaries emit before their month rows; year summary inserted before first loaded month of completed year page
  - Frontend `src/Frontend.elm`: Page merge normalization hoists year summary arriving on later page above already-loaded months for that year
- **Regression Coverage:**
  - `tests/BackendTests.elm`: Boundary markers (Y 2025 → M 2025-04 → T 2025-04-15) assert ordering on both initial and load-more paths
  - `tests/FrontendTests.elm`: Pagination merge tests verify year summary hoisting on load-more
- **Validation:** elm-format, lamdera make src/Frontend.elm, lamdera make src/Backend.elm, npm test (57/57 pass), HTTP 200
- **Verdict:** Vasquez approved; commit e36ea18 production-ready
- **Decision merged:** Summary Header Ordering (2026-05-15)

### 2026-05-15T17:15:00Z: Reverse Chronology Follow-up Review — REJECTED ❌

- **Task:** Review Dallas's chronology follow-up for the group transaction list after summary headers were moved above period blocks
- **Findings:**
  - `src/Backend.elm` still builds month rows through `groupTransactionsForMonth` without an explicit descending day/index guarantee, so strict reverse chronology is not proven for rows inside a month.
  - `tests/BackendTests.elm` and `tests/FrontendTests.elm` only prove header placement and merge shape; they do not assert actual row order across day or same-day seams.
- **Validation:** elm-format ✅, lamdera make src/Frontend.elm ✅, lamdera make src/Backend.elm ✅, npm test (57/57) ✅, HTTP 200 ✅
- **Verdict:** Rejected pending explicit reverse-chronology coverage across summary rows and pagination seams

### 2026-05-15T16:20:00Z: Deep-Page Reload State Review — REJECTED ❌

- **Task:** Review the follow-up fix for incremental transaction loading where add/edit should reload as many pages as were already visible.
- **Findings:**
  - `src/Types.elm` / `src/Frontend.elm` still only track `groupTransactionsNextCursor` and `groupTransactionsLoading`; there is no frontend model field recording loaded page depth.
  - `src/Frontend.elm`'s `OperationSuccessful` branch still reloads with a single `RequestGroupTransactions { before = Nothing }`, so editing or adding from older pages will jump the list back toward newer history.
  - `tests/FrontendTests.elm` and `tests/MigrationTests.elm` do not prove the deep-page reload seam, and the generated `src/Evergreen/Migrate/V34.elm` plus `src/Evergreen/V34/Types.elm` are still present instead of being removed pending explicit migration approval.
- **Validation:** elm-format ✅, lamdera make src/Frontend.elm ✅, lamdera make src/Backend.elm ✅, npm test (57/57) ✅
- **Verdict:** Rejected until the frontend persists loaded-page depth across refreshes, tests cover the composed deep-page reload seam without disturbing chronology/header placement, and the stale generated migration artifacts are deleted rather than refreshed.

### 2026-05-15T16:40:00Z: Deep-Page Reload State Review (commit 8224e1b) — REJECTED ❌

- **Task:** Review Newt's follow-up commit `8224e1b` for preserved paginated transaction reload depth after add/edit refreshes.
- **Findings:**
  - `src/Types.elm` and `src/Frontend.elm` now remember reload depth through `groupTransactionsLoadedPages`, and `OperationSuccessful` does reissue `requestInitialGroupTransactions model.group model.groupTransactionsLoadedPages`.
  - The stale generated artifacts were handled per user instruction: `src/Evergreen/Migrate/V34.elm` and `src/Evergreen/V34/Types.elm` are deleted rather than regenerated.
  - Chronology/header guards remain present in `tests/FrontendTests.elm` and `tests/BackendTests.elm`, but the new reload-depth coverage only exercises `groupTransactionsReloadPages` and `updatedGroupTransactionsLoadedPages` as pure helpers. It still does **not** prove the composed several-pages-down mutation path (`OperationSuccessful` -> reload request -> same-depth response), which is the exact seam that regressed.
- **Validation:** elm-format ✅, lamdera make src/Frontend.elm ✅, lamdera make src/Backend.elm ✅, npm test (58/58) ✅, localhost:8000 HTTP 200 ✅
- **Verdict:** Rejected. Newt remains locked out for the next revision cycle until another agent adds explicit regression coverage for the mutation-triggered deep-page refresh path.

### 2026-05-15T16:10:58Z: Deep-Page Refresh Proof Review (current artifact) — REJECTED ❌

- **Task:** Review Hudson's follow-up artifact for the incremental-loading refresh bug, with emphasis on proof that several-pages-down add/edit flows reload the same depth.
- **Findings:**
  - `src/Types.elm` / `src/Frontend.elm` still contain the intended stateful fix: `groupTransactionsLoadedPages` is tracked and `OperationSuccessful` reuses it through `requestInitialGroupTransactions`.
  - The stale generated migration artifacts remain correctly deleted: no `src/Evergreen/Migrate/V34.elm` or `src/Evergreen/V34/Types.elm` is present.
  - The remaining seam is unchanged: `tests/FrontendTests.elm` still has no regression that drives the actual `OperationSuccessful` / `updateFromBackend` branch. Coverage stops at helper math (`groupTransactionsReloadPages`, `updatedGroupTransactionsLoadedPages`), so the composed deep-page refresh path is still unproved even though chronology/header guards remain elsewhere.
- **Validation:** elm-format ✅, lamdera make src/Frontend.elm ✅, lamdera make src/Backend.elm ✅, npm test (58/58) ✅, localhost:8000 HTTP 200 ✅
- **Verdict:** Rejected again. Hudson is now locked out for the next revision cycle until a different agent adds an explicit mutation-refresh regression at the message/update seam.

### 2026-05-15T16:17:14Z: Deep-Page Refresh Proof Review (commit 06940a4) — APPROVED ✅

- **Task:** Review commit `06940a4` for the incremental-loading refresh bug, with explicit proof that add/edit success several pages down re-requests the same depth.
- **Findings:**
  - `src/Frontend.elm` now extracts `operationSuccessfulRefreshPlan`, and `updateFromBackend OperationSuccessful` consumes that plan directly, so the replay request is testable without drifting away from production behavior.
  - `tests/BackendTests.elm` adds a composed regression that loads two pages, records the remembered depth, runs the operation-success refresh plan, replays the resulting `RequestGroupTransactions { before = Nothing, pages = 2 }`, and proves the refreshed list still contains the older April month in reverse chronology with headers leading each block.
  - Existing chronology/header guards remain in place in `tests/FrontendTests.elm` and `tests/BackendTests.elm`, and the stale V34 migration artifacts remain deleted: there is no `src/Evergreen/Migrate/V34.elm` or `src/Evergreen/V34/Types.elm`.
- **Validation:** elm-format ✅, lamdera make src/Frontend.elm ✅, lamdera make src/Backend.elm ✅, npm test (59/59) ✅, localhost:8000 HTTP 200 ✅
- **Verdict:** Approved. The deep-page refresh seam is now explicitly proved at the composed flow level.

### 2026-05-15T18:10:00Z: Late-Arriving Year Summary Review — APPROVED ✅

- **Task:** Review Bishop's follow-up for the seam where an older year first appears on a later page load and must already show its year summary/header.
- **Findings:**
  - `src/Backend.elm` now carries year totals on every month slice, then emits year summaries whenever a page spans multiple years or reaches the visible end of a year. That closes the bug where page 2 could introduce a new older year but miss its header until page 3.
  - `tests/BackendTests.elm` now adds the right regression shape: page 1 shows only 2025, page 2 first introduces 2024 while that year is still only partially loaded, and the assertions check the exact `Y 2024 -> M 2024-12 -> T 2024-12` placement both on the second page itself and after frontend merge.
  - Existing safeguards remain intact: reverse-chronology coverage still passes, deep-page refresh proof remains in place, and `src/Evergreen/Migrate/V34.elm` plus `src/Evergreen/V34/Types.elm` stay deleted.
- **Validation:** elm-format ✅, lamdera make src/Frontend.elm ✅, lamdera make src/Backend.elm ✅, npm test (60/60) ✅, localhost:8000 HTTP 200 ✅
- **Verdict:** Approved. The late-arriving year-summary seam is now explicitly proved instead of being inferred from generic header counts.

### 2026-05-15T16:43:52Z: Late-Arriving Year Header Safety Review — APPROVED ✅

- **Task:** Review Bishop's fix for the late-arriving year header seam when older year first appears on page 2.
- **Approach:**
  - Verified backend logic: year total on every month slice + header emission when page spans multiple years
  - Confirmed page 2 can introduce 2024 and render `Y 2024` immediately even when 2024 continues to later page
  - Checked test quality: exact failure shape (page 1 = 2025, page 2 = first 2024) with `Y 2024 -> M 2024-12` ordering verified both in payload and after frontend merge
- **Regression Gates Validated:**
  - Reverse chronology tests: still pass ✓
  - Deep-page reload proof: remains intact ✓
  - Migration safety: No Evergreen artifacts generated (`V34/Migrate/` and `V34/Types.elm` stay deleted) ✓
- **Validation:** elm-format ✅, lamdera make src/Frontend.elm ✅, lamdera make src/Backend.elm ✅, npm test ✅, localhost:8000 HTTP 200 ✅
- **Verdict:** Approved. The late-arriving year seam is now explicitly fixed with comprehensive regression proof; all safety rails remain in place.
- **Status:** Ready for production merge
