---
name: "month-fold-state-without-migration"
description: "Keep foldable Lamdera month sections stable across rerenders without changing persisted frontend model shape"
domain: "frontend-state"
confidence: "high"
source: "earned"
---

## Context
Use this when an Elm/Lamdera transaction list already stores heterogeneous summary/row items, product wants foldable month sections, and the revision must avoid Evergreen migration work.

## Patterns
- Keep fold state keyed by `(year, month)`, never by list index.
- If changing `FrontendModel` would trigger migration work you are not authorized to do, encode folded state structurally in the existing list instead of adding a new persisted field.
- In a month-summary list, a duplicated `GroupTransactionMonthSummary` can act as a frontend-only folded marker while keeping the real month rows available for instant re-expansion.
- After backend reload/load-more responses, normalize the merged list first, then reapply folded markers from the pre-update list so rerenders do not reopen collapsed months.
- If folding can shrink the scrollable list enough to expose the end without a new user scroll event, re-check the scroll container viewport after the fold toggle and reuse the existing load-more threshold helper.
- Prove the real fold-to-load-more seam, not just viewport math helpers. If `Browser.Dom` tasks make the update branch opaque in tests, extract a pure follow-up plan/helper that the toggle branch consumes so tests can pin the post-fold load-more request.
- Treat extracted plan helpers as acceptable proof only when the real `update` branches are thin delegators to those helpers. If production logic diverges from the tested helper, the seam is still unproved.
- Test the composed seam: toggle one month, keep other months visible, then prove fresh reload, older-page append, and mutation-triggered refresh-depth replay all preserve the fold.

## Examples
- `src/Frontend.elm`: `toggleGroupTransactionMonthFold`, `checkGroupTransactionsViewport`, `groupTransactionViewSections`, and `applyGroupTransactionMonthFolds`.
- `tests/FrontendTests.elm`: month-fold regression cases for toggle, fresh reload, older-year load-more, viewport-triggered load-more, and `operationSuccessfulRefreshPlan`.

## Anti-Patterns
- Do not use native `<details>` as the source of truth for fold state in Elm views that rerender from model data.
- Do not add a new `FrontendModel` fold-state field when migration work is out of scope.
- Do not hide rows by deleting them from stored frontend state; you need the real rows available to restore the section instantly and to survive backend merges.
- Do not assume a fold toggle will emit a fresh scroll event; if the list height changes under a stationary viewport, pagination can stall unless you explicitly re-measure.
- Do not approve a fold-triggered pagination fix based only on `groupTransactionsScrollStateFromViewport` / `shouldLoadMoreGroupTransactions` helper tests; they do not prove that folding actually schedules the viewport check and older-page request.
