---
name: "project-conventions"
description: "Core conventions and patterns for this codebase"
domain: "project-conventions"
confidence: "high"
source: "repo-observed"
---

## Context

Lamdera changes in this repo usually flow through `src/Types.elm`, `src/Backend.elm`, `src/Codecs.elm(.stub)`, and a generated Evergreen version under `src/Evergreen/`.

## Patterns

### Lamdera model migrations

- Treat backend storage changes as migration work, not just type edits.
- After changing shared types, run `lamdera check --force` to generate the new Evergreen version, then replace generated `Unimplemented` placeholders with explicit migrations.
- Prefer rebuilding new backend storage from old persisted data rather than trying to preserve fragile positional identifiers.

### Spending and transaction persistence

- Spendings are the editable root record; dated transactions are the listed unit.
- Keep stable integer `SpendingId`/`TransactionId` counters on `BackendModel` and store bidirectional references (`Spending.transactionIds`, `Transaction.spendingId`).
- When editing, follow the existing append-only pattern: mark old records `Replaced`, remove their aggregate effects, then create fresh active records.
- When the UI is still single-bucket, adapt it through a singleton default transaction and reject edits for multi-transaction spendings rather than silently collapsing data.
- When the dialog still edits credits and debits as lists, fan them out into one-sided transaction records before persistence and rebuild bucket-level totals or member metadata in the backend from the dated transaction key.

### Code generation and validation

- Regenerate codecs with `./check-codecs.sh --regenerate` after backend model changes.
- Treat `./check-codecs.sh` as a hard review gate: Lamdera can still compile while `src/Codecs.elm` is stale relative to the generated output.
- Format with `elm-format src/ --yes` and validate with `lamdera make src/Frontend.elm --output=/dev/null`, `lamdera make src/Backend.elm --output=/dev/null`, and `lamdera check --force`.

## Anti-Patterns

- Do not hand-edit `src/Evergreen/V*/Types.elm`; generate it through Lamdera.
- Do not rely on day-list positions as durable cross-record identifiers once records reference each other.
