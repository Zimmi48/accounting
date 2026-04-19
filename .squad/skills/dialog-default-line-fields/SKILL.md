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
- Keep lightweight/collapsed-vs-expanded presentation state out of persisted child payloads; compute it from row content or store it only in dialog-local state.
- Auto-reveal detail controls when persisted child data differs from the parent default or becomes non-empty, so hidden-by-default UI does not bury meaningful edits.
- When the old UX relied on an always-available first row, normalize child-row state to one trailing placeholder entry instead of adding a large explicit “Add” button; prune fully blank extra rows back out on edit.

## Examples

- `src/Frontend.elm`: spending dialog keeps a spending-level default date, but each credit/debit line owns its own date and optional secondary description.
- `src/Frontend.elm`: the spending dialog keeps one placeholder debitor/creditor row in state so the editor behaves like the older inline-add flow without changing the persisted transaction payload.
- `src/Backend.elm`: spending validation checks `credits = debits = spending total`, while persisted transactions stay one-sided.

## Anti-Patterns

- Introducing fake bucket totals just because the UI groups rows visually.
- Pushing convenience-only parent fields into persisted child records when they are not true storage ownership.
- Adding IDs or visibility flags to persisted line payloads just to support frontend reveal/collapse behavior.
- Requiring users to press a large “Add” button just to create the first or next line when the older editor pattern already supported progressive row creation.
