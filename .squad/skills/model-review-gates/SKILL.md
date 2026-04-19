---
name: "model-review-gates"
description: "Review checklist for compile-first Lamdera model refactors"
domain: "review"
confidence: "medium"
source: "repo-observed"
---

## Pattern

For shared-model refactors, do not accept compile success by itself. Verify three seams explicitly:

1. **Identifier continuity:** compare the new shared type against the last Evergreen type when the user says an identifier shape must stay stable.
2. **Constructor fan-out:** inspect backend creation/edit paths to confirm the intended storage expansion actually happens, rather than just renaming containers.
3. **Migration discipline:** confirm no new Evergreen files appear when the user has asked to defer migration work until after review.
4. **Mirrored invariant cleanup:** when an invariant moves to a parent record, inspect both backend validation and frontend submit gating for leftover child-level equality checks.
5. **Ordering seam verification:** when UI ordering changes depend on backend traversal order, inspect the producer and consumer together. Do not accept a frontend-only `List.reverse` plus a synthetic helper test unless it matches the actual backend order contract, including same-day ties.

## Applied here

- `src/Evergreen/V24/Types.elm` preserved the old `TransactionId` locator shape, which made the regression in `src/Types.elm` easy to catch.
- `src/Backend.elm` showed the real invariant in `validateSpendingTransactions` and `createSpendingInModel`, proving the model still stores balanced buckets instead of one-sided transactions.
- Phase 2 follow-up proved the same bug can survive in two layers at once: `validateSpendingTransactions` and `canSubmitSpending` / `validTransactionLines` both need review when `Spending.total` becomes the only amount-level invariant.
- **Applied correction:** When a dated list index is the user-approved identifier shape, keep the list append-only and use status flags plus aggregate rollback instead of physically removing records; reconstruct higher-level edit payloads from grouped low-level transactions rather than changing the Phase 1 UI contract early.
- Group transaction ordering review exposed another seam: `src/Backend.elm` can already emit rows newest-first via `Dict.foldr`, so a frontend reversal helper and a test built from a synthetic ascending list can both pass while the real UI order regresses.

## Examples

- Spending-level invariant repairs belong in the backend seam that sees the full normalized transaction list. In this repo, `src/Backend.elm:validateSpendingTransactions` is the review point for `sum(credits) = sum(debits) = spending.total`; line validation should stay limited to line completeness unless the user explicitly asks for mirrored frontend gating.
- For transaction list ordering in this repo, review `src/Backend.elm:RequestGroupTransactions` together with `src/Frontend.elm:ListGroupTransactions`; if the backend already imposes newest-first order, the frontend should preserve that response and the regression test should hit the consumer seam directly rather than a standalone reversal helper.

## Anti-Patterns

- Do not "fix" a spending-level invariant regression by reintroducing old bucket-level equality rules. If the contract says totals live on `Spending`, restore the aggregate check after normalization and leave line-level date/description shape alone.
