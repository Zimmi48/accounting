# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Full-stack group expense and accounting app with shared models, backend logic, and Elm UI.
- **Created:** 2026-04-20

## Learnings

- Joined to own full-stack recovery and compile-first revisions after prior authors were locked out on the spending/transaction split artifact.
- User directive: do not generate the Evergreen migration before Théo reviews the model changes.
- Compile-first split shape: `BackendModel` now keeps `spendings : Dict SpendingId Spending` plus dated `Day.transactions`, with `Spending.transactionIds` and `Transaction.spendingId` as the cross-reference seam.
- Phase 1 edit/delete contract lives in `src/Types.elm`, `src/Backend.elm`, `src/Frontend.elm`, and `src/Codecs.elm`; the frontend still submits one default transaction bucket using the dialog date and an empty secondary description.
- `RequestSpendingDetails` is the safe bridge for the old dialog: backend returns one editable bucket for singleton spendings and rejects multi-transaction spendings until the later UI pass.
- `2026-04-20T16:43:52Z`: Model-only spending/transaction split approved for user review
- `2026-04-21`: The rejected Phase 2 seam in `74261e3` lived in mirrored total checks, not the shared model shape: `src/Backend.elm` still required `credits == debits == total`, and `src/Frontend.elm` still blocked submit unless each side summed to `total`.
- `2026-04-21`: The recovery fix keeps `Spending.total` as the only amount-level invariant, while line items remain ID-free and still validate per-line date, group, and positive amount; validation stayed on `elm-format src/ --yes`, both `lamdera make` targets, and `lamdera live` returning HTTP 200 with no `src/Evergreen/` diff.

## 2026-04-21: Phase 2 Contract Correction Verdict

- **Session timestamp:** 2026-04-21T06:49:24Z
- **Status:** Rejected — commit `50629e3` dropped the spending-level invariant entirely
- **Correction:** Hudson's commit `b7d0444` restored invariant in `validateSpendingTransactions`
- **Outcome:** Team stack approved; Newt's work rejected but contributed to understanding
- **Next phase:** Await Théo's data model review and Evergreen migration planning

