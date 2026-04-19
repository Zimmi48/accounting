---
name: "lightweight-row-details"
description: "Keep editable rows compact while auto-revealing meaningful per-row details"
domain: "ui-contracts"
confidence: "medium"
source: "earned"
---

## Context

Use this when each row owns real persisted detail fields, but the fully expanded form is visually heavier than the common editing path.

## Patterns

- Put the primary row fields first so scanning and quick edits happen without opening secondary controls.
- When a row needs an identity cue like “Debitor 1”, prefer making that the visible label of the primary field instead of adding a separate mini-header above the row.
- Hide secondary controls behind an explicit reveal affordance for default/empty rows.
- Auto-show the secondary controls whenever persisted detail data is already meaningful (for example a custom date or non-empty secondary description).
- Prefer an explicit helper that compares each row against the parent default, so the auto-reveal rule stays aligned with the same default-propagation seam that updates untouched rows.
- Keep reveal state frontend-local; do not push presentation-only flags into backend contracts.
- If generic icon packages do not match the semantics of compact row controls, a tiny local inline-SVG helper can be cleaner than adding a dependency with the wrong visual language.
- When a revealed detail row mirrors the primary row semantically, keep both rows on the same width contract across breakpoints instead of letting the detail row stretch wider.
- A practical Elm UI split is: desktop uses one flexible field plus one compact fixed-width field; small screens switch both paired fields to equal `fillPortion` widths.
- If two labeled controls need to match as whole blocks, put the shared width on an outer `el` wrapper and let the inner `Input` or `DatePicker.input` use `width fill`; this avoids component-specific label/layout differences from breaking alignment.
- If sibling row lists share a normalization pass, keep passive normalization from auto-seeding placeholder values on the untouched side; only the side the user is actively adding should receive any convenience default.

## Examples

- `src/Frontend.elm`: spending lines now show group and amount inline, while per-line date and secondary description stay collapsed unless revealed or already customized.
- `src/Frontend.elm`: spending rows use the group field label (`Debitor 1`, `Creditor 1`) as the row identifier, with compact inline SVG controls for details/remove.
- `src/Frontend.elm`: the spending dialog now shares the same desktop/small-screen width split between `Group/Amount` and `Description/Date`, so expanding details does not widen the visual grid.
- `src/Frontend.elm`: wrapping both the amount field and the date picker in width-constrained `el` blocks keeps the full `Amount + field` and `Date + field` columns aligned, not just the inner inputs.
- `src/Frontend.elm`: `normalizeSpendingDialogLines` should use `normalizeTransactionLinesWithoutAutofill` for passive cleanup, so typing on debitors cannot silently prefill creditor amounts.

## Anti-Patterns

- Forcing every row into a card-style expanded layout when most rows use defaults.
- Letting users hide customized detail fields so far that meaningful differences from the parent default disappear.
- Using a separate bold row title and a hidden primary-field label when one visible field label would carry the same meaning with less visual noise.
- Giving the secondary row more horizontal budget than the primary row, or letting compact fields like dates grow wider than their amount counterparts.
- Applying width only to the inner control when the surrounding labeled block is what needs to align across different component types.
- Reusing an autofill-oriented normalizer for both debit and credit lists after every keystroke, which can leak placeholder amounts into the opposite untouched side.
