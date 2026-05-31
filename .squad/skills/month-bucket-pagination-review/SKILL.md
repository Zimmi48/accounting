---
name: "month-bucket-pagination-review"
description: "Review and test Lamdera transaction lists that paginate by whole months while injecting year/month summaries"
domain: "testing"
confidence: "medium"
source: "earned"
---

## Context
Use this when a group transaction list stops returning the full history at once and instead loads the newest whole months needed to satisfy a transaction target, while also rendering summary rows for each loaded month and year.

## Patterns
- Treat the page unit as a whole month, not an arbitrary row count. The key regression seam is the 100-transaction threshold crossing a month boundary.
- Prove both pagination boundaries: exactly 100 transactions in the newest month, and fewer than 100 in the newest month so the next month must be pulled in whole.
- Separate backend and frontend responsibilities in tests: backend proves which months/summaries belong to a page and that summary markers lead each year/month block; frontend proves merge order, stale-response rejection, and reset on group change.
- When the frontend re-normalizes merged `GroupTransactionListItem`s to hoist summary headers, sort rows explicitly by descending `(year, month, day, transactionId.index)` instead of trusting backend arrival order; otherwise header fixes can quietly preserve oldest-first rows inside a month.
- Pin summary totals to persisted aggregates (`StoredGroup.totalCredit`, `Year.totalCredit`, `Month.totalCredit`) instead of recomputing from the visible slice. Otherwise pagination can make tests pass while summary math drifts.
- For Lamdera migrations, do not trust old cached flat transaction lists to become paginated summary-aware state automatically. Prefer clearing cached list/cursor state or a narrowly safe upgrade plus a refetch.
- Re-test list refresh seams such as toggle/edit/delete after pagination lands. A response shape change can silently collapse already loaded older pages back to page 1.
- If add/edit/delete now trigger a list refetch, store the loaded-page depth (or equivalent replayable pagination state) in the frontend model and prove that refresh re-requests the same depth instead of only page 1.
- For mutation-triggered refreshes, helper-only tests are not enough: assert the actual frontend update branch (for example `OperationSuccessful`) emits the replay request with the remembered depth, otherwise the regression seam remains unproved.
- When Lamdera `Cmd`s make that branch opaque in tests, extract a pure "refresh plan" helper that the update branch consumes so tests can assert the exact `RequestGroupTransactions` replay without mocking runtime internals.
- Compress rendered pages into summary/period-boundary markers (for example `Y 2025`, `M 2025-04`, `T 2025-04`) so tests prove summaries lead each year/month block without snapshotting every row.
- Add a dedicated seam case where page 1 contains only newer years and page 2 is the first page that introduces an older year. Make that older year large enough that its summary-carrying oldest month would normally fall on page 3; otherwise the reported missing-year-line bug stays hidden.
- When a load-more request starts with the first month of a newly visible older year, emit that year summary immediately based on the request cursor seam, even if the returned page stays within one year and does not yet reach that year's oldest loaded month.
- Keep both boundary shapes in coverage: one later page that introduces year `Y` and also includes an even older year header, and one that introduces `Y` but stays entirely inside `Y`. Either case alone can miss the neighboring skipped-year bug.
- If months become foldable in the UI, key folded state by `(year, month)` rather than list index so pagination merges and refresh replays cannot collapse the wrong month after headers are re-normalized.
- For month folding, frontend tests must prove the composed seam: a selected month summary stays visible, only that month's rows hide/show, untouched months keep their chronology/header order, and load-more plus mutation-triggered refreshes do not disturb either the folded choice or the remembered page depth.
- If dialogs can stay open above the transaction list, add frontend regression coverage proving that dialog presence does not suppress the existing load-more and fold-triggered viewport-check plans. Treat actual wheel/touch scroll-through as a separate view-level seam if pure helper tests cannot observe DOM event routing.

## Examples
- `src/Backend.elm`: current `groupTransactionsForName` emits the entire active history, so a progressive-loading rewrite needs explicit boundary tests around the replacement helper.
- `src/Frontend.elm`: `groupTransactionsFromBackend` should normalize merged `GroupTransactionListItem`s so later year-boundary pages can hoist their year summary above already-loaded newer months.
- `src/Frontend.elm`: `operationSuccessfulRefreshPlan` lets tests inspect the exact multi-page refetch requested after add/edit/delete success without needing to unwrap Lamdera `Cmd`s.
- `src/Frontend.elm`: any month-folding view/helper should decide row visibility from a stable month key and leave `GroupTransactionMonthSummary` rendered even when that month is collapsed.
- `tests/MigrationTests.elm`: use migration tests to ensure old `RequestGroupTransactions` / `ListGroupTransactions` payloads and cached frontend state cannot be misread as the new paginated contract.

## Anti-Patterns
- Do not approve pagination based only on a happy-path first page with fewer than 100 rows.
- Do not split a month to hit the row target exactly unless the product explicitly changes the month-as-page-unit rule.
- Do not recompute summary totals from the currently loaded rows when persisted bucket totals already exist.
- Do not ignore refresh paths (toggle, edit, delete); they often reuse the old full-list response contract and can regress after pagination.
- Do not approve a deep-page reload fix based only on pure helper tests for page-count math; that misses the real message/update seam where the refresh request is constructed.
- Do not approve ordering changes based only on summary counts or totals; a list can have the right aggregates while still rendering every summary below its period rows.
- Do not rely on `Y/M/T` boundary markers alone to prove reverse chronology; they intentionally collapse many transactions into one marker and can miss day-level or same-day ordering regressions.
- Do not treat a later-page year-summary test as sufficient when that page also reaches the end of the year; that only proves the boundary month case, not the seam where a year first appears before its oldest month is loaded.
- Do not approve month folding when tests only prove that some rows disappeared; without month-specific assertions, the implementation may be hiding the wrong month, the header itself, or later paginated rows.
- Do not hide fold state inside a migration-bearing shared type change unless migration work is explicitly requested and reviewed; UI-local fold state should stay frontend-local whenever possible.
