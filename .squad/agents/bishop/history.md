# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Group expense and accounting app with Lamdera backend and evergreen migrations.
- **Created:** 2026-04-19

## Learnings

- Initial roster assignment: Backend, model changes, and Lamdera migration ownership.
- 2026-04-19: Spending/transaction split landed in `src/Types.elm`, `src/Backend.elm`, and `src/Evergreen/Migrate/V26.elm`. Backend storage now separates `spendings : Dict SpendingId Spending` from dated `Day.transactions : List Transaction`, with stable `SpendingId`/`TransactionId` counters on `BackendModel`.
- Backend edit/delete keeps the old append-only pattern: spendings and transactions are marked `Replaced`/`Deleted`, totals are removed from aggregates, and edits create a fresh spending plus fresh transactions.
- Current frontend contract preserves the existing dialog by sending a singleton `transactions` list with spending-date defaults and empty `secondaryDescription`; backend normalization still merges by `(date, secondaryDescription)` bucket, summing credits and debits separately by group.
- Evergreen V26 migrates each legacy day spending into one stored spending plus one transaction with empty secondary description, while frontend/session migration intentionally resets fragile client-side edit/delete state to safe defaults.
- Codec workflow remains `./check-codecs.sh --regenerate`, and migration validation succeeded with `lamdera check --force` after adding `src/Evergreen/V26/Types.elm` and `src/Evergreen/Migrate/V26.elm`.
- 2026-04-21: Codec parity fixes can be generation-only; for the current model shape, `./check-codecs.sh --regenerate` refreshed `src/Codecs.elm` without touching `src/Types.elm`, `src/Backend.elm`, or any `src/Evergreen/` files, and validation stayed on `elm-format`, both `lamdera make` targets, and `lamdera live` HTTP 200.

## 2026-04-21: Phase 2 Contract Correction Approved

- **Session timestamp:** 2026-04-21T06:49:24Z
- **Commit:** `862817b` — Codec parity refresh complete
- **Role:** Ensured codec alignment in `src/Codecs.elm` after model corrections
- **Outcome:** All review gates green; part of approved Hudson + Bishop stack
- **Contract:** Spending owns total invariant; transaction lines own dates/secondary descriptions
- **Next phase:** Await data model finalization for Evergreen migration

