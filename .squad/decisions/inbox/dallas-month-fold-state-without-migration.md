# Month fold state without migration

- **Context:** The rejected month-folding revision used native `<details>` state, which reopened collapsed months on rerender. The replacement had to remember folds across pagination and refresh without opening Evergreen migration work.
- **Decision:** Keep month fold state frontend-local by encoding it in `groupTransactions` with a duplicated `GroupTransactionMonthSummary` marker for folded months, keyed by `(year, month)`.
- **Why:** This preserves fold state across normal list normalization, load-more merges, and mutation-triggered refresh replays without changing `FrontendModel` shape or introducing migration work.
- **Implementation notes:** `toggleGroupTransactionMonthFold` flips the marker, `groupTransactionViewSections` interprets it, and `groupTransactionsFromBackend` reapplies remembered folded months after normalizing backend items.
