---
name: "progressive-group-transaction-loading"
description: "Paginate Lamdera group transaction lists by month while preserving period summaries and migration safety"
domain: "frontend-backend-contracts"
confidence: "high"
source: "earned"
---

## Context
Use this when the UI should load a group's transactions incrementally, but the stored data is already grouped by year and month. It applies especially when period summaries must remain coherent and the shared Lamdera contract changes enough to require an Evergreen migration.

## Patterns
- Page by whole months, not raw row counts. Count transaction rows toward the 100-row threshold, but always include complete month buckets.
- Use an explicit cursor contract like `{ group, before : Maybe { year, month } }` so the frontend appends older pages without inventing offsets.
- Track how many pages the active group has already loaded, and let refresh-triggering requests ask for that many pages again so add/edit/delete flows do not snap the user back to page 1.
- Return heterogeneous list items from the backend (`transaction row`, `month summary`, `year summary`) instead of asking the frontend to reconstruct period boundaries from flat rows.
- Emit month summaries as headers before each month's rows. Preserve the existing single-year partial-page behavior, but if one response spans multiple visible years, include a year summary for each visible year block so an older year does not arrive headerless on a later page.
- When a later page introduces an older visible year, normalize the merged frontend list so that the new year summary moves above the already-loaded newer months from that same year.
- In frontend migrations, preserve legacy listed rows by wrapping them in the new row constructor, but reset new pagination-only state to safe defaults.

## Examples
- `src/Types.elm` adds `GroupTransactionsCursor`, `GroupTransactionListItem`, and the paged `RequestGroupTransactions` / `ListGroupTransactions` payloads.
- `src/Backend.elm` uses `groupTransactionMonthSlices`, `groupTransactionPageItems`, and `takeTransactionMonthSlices` to build 100-row month pages while preserving header-first summary placement.
- `src/Frontend.elm` stores `groupTransactionsLoadedPages`, reloads with that count after `OperationSuccessful`, and keeps scroll-driven pagination on `pages = 1`.
- `src/Evergreen/Migrate/V34.elm` maps legacy flat transaction rows to `GroupTransactionRow` and resets `groupTransactionsNextCursor` / `groupTransactionsLoading`.

## Anti-Patterns
- Do not paginate by array index when the storage contract is month-bucketed.
- Do not leave the oldest visible year in a multi-year response without a header just because older months from that same year still exist on later pages.
- Do not force the frontend to guess pagination state from the current rendered list.
- Do not leave year-summary placement to naive page concatenation; append-only merging will strand the header below newer months unless the frontend re-normalizes the combined list.
