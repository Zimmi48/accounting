---
name: "modal-mask-wheel-scroll"
description: "Restore wheel scrolling behind a modal when the background content moved into its own scroll viewport"
domain: "frontend-ui"
confidence: "medium"
source: "earned"
---

## Context
Use this when a modal dialog still needs to block background clicks, but the user must be able to wheel-scroll a specific background list. It is especially useful after a refactor moves content from page scroll into an inner scroll container.

## Patterns
- Keep the dialog mask active for clicks; do **not** solve the problem by disabling mask pointer events.
- Attach a `wheel` handler to the mask and decode `deltaY`.
- Convert that wheel delta into a pure scroll plan using the target viewport's current `Browser.Dom.getViewportOf` position.
- Apply the plan with `Browser.Dom.setViewportOf` so the existing scroll listeners, pagination, and fold logic stay in one place.
- Guard the handler so it only activates on pages that actually have the intended background viewport.

## Example
- `src/Frontend.elm` routes `DialogMaskWheelScrolled deltaY` into `#group-transactions-list` while preserving the grouped transaction dialog mask.
- `tests/FrontendTests.elm` asserts the pure `groupTransactionsDialogMaskScrollPlan` target/clamp behavior instead of comparing opaque `Cmd` values.

## Anti-Patterns
- Do not set the mask to `pointer-events: none`; that re-enables accidental background clicks.
- Do not duplicate pagination logic in the modal handler; let the existing viewport scroll path react naturally.
- Do not make the wheel handler global if only one page owns the background viewport.
