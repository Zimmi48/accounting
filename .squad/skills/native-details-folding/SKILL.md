---
name: "native-details-folding"
description: "Add foldable frontend-only list sections without introducing Lamdera model migrations"
domain: "ui-contracts"
confidence: "medium"
source: "earned"
---

## Context

Use this when a Lamdera list already has stable summary/header rows and the product only needs a presentation-level fold/unfold affordance.

## Patterns

- Prefer grouping existing list items in `src/Frontend.elm` over changing shared `src/Types.elm` contracts when the collapsed/expanded state does not affect backend behavior.
- Native `<details open>` is a good fit for month or section folding when “expanded by default” is acceptable and the open state does not need to survive frontend rerenders.
- Keep standalone headers (for example year summaries) outside the foldable section so chronology and pagination markers remain readable even when months collapse.
- Extract a pure helper that groups flat rendered items into foldable sections before wiring the view. That keeps regression tests fast and avoids DOM-heavy test setup.
- Add a second pure helper that defines which items remain visible when a section is folded versus expanded; use it to pin the “summary stays, rows hide” rule in tests.

## Examples

- `src/Frontend.elm`: `groupTransactionViewSections` groups a normalized transaction list into standalone year headers and `FoldableGroupTransactionMonthSection` buckets.
- `src/Frontend.elm`: `viewFoldableGroupTransactionMonthSection` reuses the existing month summary row as the `<summary>` toggle and leaves month rows inside the native details body.
- `tests/FrontendTests.elm`: `groupTransactionMonthSectionItems` proves a folded month keeps only its summary item while an expanded month keeps both the summary and its rows.

## Anti-Patterns

- Adding shared Lamdera model fields for UI-only open/closed state when native browser controls or local view grouping are sufficient.
- Recomputing pagination order inside the fold helper; keep ordering ownership with the existing normalization path.
- Hiding year headers inside month toggles, which makes older loaded pages harder to scan.
- Hard-coding `Attr.attribute "open" ""` while also expecting folded months to stay closed across Elm rerenders. Without frontend state keyed by month, load-more, refresh, or any unrelated redraw will reopen the section and the seam is not actually fixed.
