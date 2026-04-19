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
- Keep `SpendingId` append-only via `Array.length model.spendings`.
- Keep `Transaction.spendingId` as the canonical persisted membership link.
- Derive `TransactionId` positionally from append-only day storage when exact row addressing is needed; do not persist redundant transaction-id fields in backend records.
- Treat collection choice (`List` vs `Array`) as a performance detail, not an identity model. If records need durable cross-record references, define a canonical relation explicitly rather than relying on container position.
- When editing, follow the existing append-only pattern: mark old records `Replaced`, remove their aggregate effects, then create fresh active records.
- When the UI is still single-bucket, adapt it through a singleton default transaction and reject edits for multi-transaction spendings rather than silently collapsing data.
- When the dialog still edits credits and debits as lists, fan them out into one-sided transaction records before persistence and rebuild bucket-level totals or member metadata in the backend from the dated transaction key.

### Code generation and validation

- Regenerate codecs with `./check-codecs.sh --regenerate` after backend model changes.
- Treat `./check-codecs.sh` as a hard review gate: Lamdera can still compile while `src/Codecs.elm` is stale relative to the generated output.
- Do not hand-edit `elm.json` when adding tests; install `elm-test` with npm and initialize it via `elm-test init --compiler "$(which lamdera)"`.
- Keep pure regression tests under `tests/` and run them with `npm test`, which uses Lamdera as the compiler.
- After any change, run `elm-format src/ tests/ --yes`, `lamdera make src/Frontend.elm --output=/dev/null`, `lamdera make src/Backend.elm --output=/dev/null`, and `npm test`.

## Anti-Patterns

- Do not hand-edit `src/Evergreen/V*/Types.elm`; generate it through Lamdera.
- Do not persist day-list positions separately from the append-only list they come from.
- **Do not generate Evergreen migrations without explicit user approval.** If schema changes are necessary, document the change in decisions.md and wait for user directive before running `lamdera check --force` or creating migration files.
