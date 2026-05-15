---
name: "transaction-check-toggle-migration"
description: "Add a persisted transaction-level boolean flag without disturbing the spending editor contract"
domain: "lamdera-migrations"
confidence: "medium"
source: "earned"
---

## Context
Use this when a Lamdera change adds a lightweight per-transaction flag that is visible in list views but should not expand the existing spending editor payload.

## Patterns
- Treat a new persisted boolean on `Transaction` as storage work: update `src/Types.elm`, backend constructors, `src/Codecs.elm`, and Evergreen together.
- Default legacy and freshly created rows to `False` in migrations and backend constructors unless the old model already encoded equivalent truth data.
- Thread the flag through lightweight list payloads (`RequestGroupTransactions` / `ListGroupTransactions`) so the UI can toggle it without reopening the spending editor.
- Preserve the flag on logically unchanged rows during spending edits by reusing the existing reconciliation path instead of rebuilding every transaction from scratch.
- When the list affordance is only a colored dot, make the marker own its fill directly (for example, an elm-ui `el` with explicit `Background.color`) and drive it from a small pure state helper; avoid raw SVG `currentColor` seams that can toggle data without changing the visible dot.

## Examples
- `src/Backend.elm`: `toggleTransactionCheckedInModel`, `groupTransactionsForName`, and `preserveEditedTransaction` keep list toggles local while edit reconciliation retains checked state.
- `src/Evergreen/Migrate/V33.elm`: backend storage, frontend cached group transactions, and `ToFrontend.ListGroupTransactions` all default the new boolean to `False`.
- `tests/BackendTests.elm` and `tests/MigrationTests.elm`: cover preserved checked rows, toggled list output, and migration defaults.
- `src/Frontend.elm`: `transactionCheckVisualState`, `transactionCheckButtonStyle`, and `transactionCheckIndicator` keep the gray/green marker explicit instead of inherited; `tests/FrontendTests.elm` composes the optimistic toggle helper with the backend refresh helper so the visible checked state stays covered.

## Anti-Patterns
- Do not add the flag only to the frontend list model; import/export and persisted Lamdera state will drift immediately.
- Do not push the flag into `SpendingTransaction` unless the spending dialog is explicitly being expanded to edit it.
- Do not rebuild unchanged edited rows as fresh transactions, or the reconciliation marker will be lost on ordinary edits.
- Do not rely on inherited text color or a raw SVG `currentColor` seam as the only checked/unchecked cue without a regression test that exercises the click-plus-refresh path.
