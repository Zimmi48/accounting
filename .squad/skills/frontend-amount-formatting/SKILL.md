---
name: "frontend-amount-formatting"
description: "Reuse the canonical frontend amount formatter instead of introducing duplicate cents-to-string helpers"
domain: "frontend"
confidence: "high"
source: "earned"
---

## Context

Use this when frontend code needs to turn integer cents into the decimal strings shown in views or prefilled form fields. In this repo, the same formatting contract must work for display-only views and spending-editor hydration.

## Patterns

- Treat `src/Frontend.elm:viewAmount` as the canonical cents-to-string formatter.
- Prefer reusing `viewAmount` in edit-flow hydration helpers instead of adding a second formatter with the same output shape.
- Keep regression coverage on the pure seam by round-tripping formatted strings through `parseAmountValue` in `tests/FrontendTests.elm`.

## Examples

- `transactionLineFromSpendingTransaction` uses `viewAmount amount` when rebuilding a dialog line from stored transactions.
- `SpendingDetails` uses `viewAmount` when prefilling the dialog total from backend data.
- `tests/FrontendTests.elm` verifies representative cent values survive `viewAmount >> parseAmountValue`.

## Anti-Patterns

- Adding a new helper that duplicates `viewAmount` for form-prefill code.
- Letting display formatting and editable amount formatting drift apart.
