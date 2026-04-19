---
name: "dialog-default-line-fields"
description: "Keep convenience defaults at dialog level while persisting ownership on individual lines"
domain: "ui-contracts"
confidence: "medium"
source: "earned"
---

## Context

Use this when a parent form needs a convenience field (like a shared date) but the persisted data really belongs on child rows. It helps keep the storage model honest without making data entry painful.

## Patterns

- Store the invariant or aggregate on the true root record, not on UI grouping containers.
- Let each child row own its persisted fields, even if the dialog also exposes a parent-level default.
- When the default changes, only rewrite child rows that are still using that default or are blank; leave explicitly customized rows alone.
- When a child row intentionally keeps its persisted field empty until user action, the view layer can still pass the parent default as the control's selected/displayed value so the picker reflects the effective default without forging persisted data.
- When hydrating an edit form from persisted child rows, convert any child value that matches the parent default back into the child's implicit/default representation (for example `Nothing`) so the UI preserves the difference between inherited and explicit values across round-trips.
- If the child control has its own UI model (for example `DatePicker.Model`), seed newly created child models from the dialog-local default context too; updating only the already-existing models later will miss placeholder rows or freshly loaded rows recreated after that update.
- Keep lightweight/collapsed-vs-expanded presentation state out of persisted child payloads; compute it from row content or store it only in dialog-local state.
- Auto-reveal detail controls when persisted child data differs from the parent default or becomes non-empty, so hidden-by-default UI does not bury meaningful edits.
- When the old UX relied on an always-available first row, keep the add affordance in the view with one virtual trailing placeholder row; create a real row only when the user actually edits that virtual row, and do not silently delete real blank rows unless the product explicitly asks for cleanup.
- Gate a virtual trailing row on the specific prerequisite field that unlocks the next entry step (here: every current group name is non-empty), not necessarily on full row validity, so inline entry stays progressive without storing placeholders.

## Examples

- `src/Frontend.elm`: spending dialog keeps a spending-level default date, but each credit/debit line owns its own date and optional secondary description.
- `src/Frontend.elm`: row date pickers render `line.date |> Maybe.orElse spendingDate` so default/today appears selected even while untouched rows still persist `Nothing`.
- `src/Frontend.elm`: `transactionLineFromSpendingTransaction` treats any loaded transaction date equal to the dialog spending date as implicit and stores it back as `Nothing`, preserving explicit-vs-default date semantics when editing an existing spending.
- `src/Frontend.elm`: initialize line `DatePicker.Model` values from dialog-local `today` and then call `DatePicker.setVisibleMonth` for the effective month, so the calendar shows both the selected/default day and the today marker.
- `src/Frontend.elm`: `transactionLineInputs` appends one virtual debitor/creditor row in the view when every current row already has a non-empty group name (or there are no rows yet), while real blank rows remain in `AddSpendingDialogModel.credits` / `.debits` until the user removes them.
- `src/Backend.elm`: spending validation checks `credits = debits = spending total`, while persisted transactions stay one-sided.

## Anti-Patterns

- Introducing fake bucket totals just because the UI groups rows visually.
- Pushing convenience-only parent fields into persisted child records when they are not true storage ownership.
- Adding IDs or visibility flags to persisted line payloads just to support frontend reveal/collapse behavior.
- Recreating child `DatePicker.Model` values from `DatePicker.init` alone after `today` has already been learned; that silently drops the calendar's today highlight even if older rows were repaired with `DatePicker.setToday`.
- Requiring users to press a large “Add” button just to create the first or next line when the older editor pattern already supported progressive row creation.
- Persisting a fake trailing blank row in dialog state when a virtual view-only row can provide the same inline-add affordance with less model noise.
- Auto-pruning user-created blank rows on unrelated edits (date changes, detail toggles, autocomplete, etc.) when the intended UX is “blank rows stay until removed.”
- Blocking the next virtual row on unrelated fields like amount/date validity when the UX only needs the current naming step to be complete.
