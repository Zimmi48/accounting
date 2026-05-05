---
name: "spending-validation"
description: "Validate Lamdera spending payloads without rejecting balanced mixed-sign lines"
domain: "backend-validation"
confidence: "medium"
source: "earned"
---

## Context
Use this when changing spending creation or edit flows in this Lamdera repo. The frontend dialog can emit signed creditor/debitor amounts, so backend validation must enforce the spending-level balance invariant without silently deleting legitimate negative rows.

## Patterns
- Normalize spending transactions by merging duplicate `(date, secondaryDescription, group, side)` keys first.
- Drop only normalized rows whose combined amount is exactly zero.
- Require non-empty groups and non-zero normalized amounts, but do not require each individual row to be positive.
- Keep the final invariant at spending scope: `sum credits == sum debits == spending.total`, with `spending.total /= 0` so balanced negative spendings remain valid.

## Examples
- `src/Backend.elm`: `normalizeSpendingTransactions` should keep `Amount -100` rows and only filter out `Amount 0`.
- `tests/BackendTests.elm`: cover a balanced case like total `100`, creditors `200` and `-100`, debitors `100`.

## Anti-Patterns
- Filtering normalized transactions with `amount > 0`, which drops legitimate negative rows before totals are checked.
- Treating signed creditor/debitor rows as invalid just because their sign differs from the row's side; the side drives aggregation semantics.
- Rejecting a spending solely because its signed total is negative after the credit/debit sums already balance to that same non-zero total.
