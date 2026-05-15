---
name: "spending-edit-reconciliation"
description: "Preserve unchanged backend transaction rows when editing a spending"
domain: "backend-business-rules"
confidence: "medium"
source: "earned"
---

## Context
Use this when changing the spending edit path in this Lamdera accounting repo. The backend stores spendings append-only, but issue #49 showed that an edit should not automatically replace every old transaction when some rows are still logically the same.

## Patterns
- Normalize the submitted edit payload first, then reconcile it against the current active stored rows for that spending.
- Match rows by logical row identity `(date, secondaryDescription, group, side, amount)` rather than by slot or spending id.
- Keep matched rows active by reassigning their `spendingId` to the replacement spending instead of creating duplicate rows.
- Refresh preserved rows with the new spending-wide metadata (`groupMembersKey`, `groupMembers`) so `totalGroupCredits` stays aligned with the replacement spending.
- Mark only unmatched old rows `Replaced`, remove only their totals, and append only unmatched new rows.

## Examples
- `src/Backend.elm`: `editSpendingInModel` reconciles `plannedTransactions` before mutating statuses or totals.
- `src/Backend.elm`: `preserveEditedTransaction` keeps an unchanged row in place while moving it to the replacement spending.
- `tests/BackendTests.elm`: the preserved-transaction regression verifies unchanged rows stay active on the new spending and only changed rows are marked `Replaced`.

## Anti-Patterns
- Marking every old transaction `Replaced` before checking whether the edited row is actually unchanged.
- Matching by append-only slot index, which confuses stable storage location with logical identity.
- Preserving a row without updating its spending-wide metadata, which can leave aggregate keys drifting from the replacement spending.
