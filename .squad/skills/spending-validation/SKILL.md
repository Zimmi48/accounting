---
name: "spending-validation"
description: "Keep frontend and backend spending validation aligned for signed balanced totals"
domain: "frontend-backend-validation"
confidence: "medium"
source: "earned"
---

## Context
Use this when changing spending creation or edit flows in this Lamdera repo. The frontend dialog can emit signed creditor/debitor amounts, so both frontend submit gating and backend validation must enforce the same spending-level balance invariant without silently deleting legitimate negative rows or letting the two layers drift.

## Patterns
- Normalize spending transactions by merging duplicate `(date, secondaryDescription, group, side)` keys first.
- Drop only normalized rows whose combined amount is exactly zero.
- Require non-empty groups and non-zero normalized amounts, but do not require each individual row to be positive.
- Keep the final invariant at spending scope: `sum credits == sum debits == spending.total`, with `spending.total /= 0` so balanced negative spendings remain valid.
- Reuse the same invariant in `src/Frontend.elm:canSubmitSpending` and in the submit path itself so the disabled button state matches what `Submit` will actually send.

## Examples
- `src/Backend.elm`: `normalizeSpendingTransactions` should keep `Amount -100` rows and only filter out `Amount 0`.
- `src/Frontend.elm`: `canSubmitSpending` should reject dialogs unless both sides sum to the signed total, and the `Submit` branch should reuse that guard.
- `tests/FrontendTests.elm`: cover balanced negative totals plus mismatch cases so button gating regressions stay visible.
- `tests/BackendTests.elm`: cover a balanced case like total `100`, creditors `200` and `-100`, debitors `100`.

## Anti-Patterns
- Filtering normalized transactions with `amount > 0`, which drops legitimate negative rows before totals are checked.
- Treating signed creditor/debitor rows as invalid just because their sign differs from the row's side; the side drives aggregation semantics.
- Rejecting a spending solely because its signed total is negative after the credit/debit sums already balance to that same non-zero total.
- Letting the frontend button-enable rule differ from the backend submission rule, which produces avoidable round-trips and confusing error messages.
