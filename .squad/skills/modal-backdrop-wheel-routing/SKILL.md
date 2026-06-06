---
name: "modal-backdrop-wheel-routing"
description: "Preserve native dialog scrolling while routing backdrop wheel gestures into a background viewport"
domain: "frontend-ui-contracts"
confidence: "medium"
source: "earned"
---

## Context
Use this when a modal backdrop must keep clicks blocked, but product still expects wheel or touchpad scrolling to move a specific background list while the modal is open.

## Patterns
- Check the modal library DOM first. If the backdrop wraps the dialog container, wheel handlers on the backdrop will also see bubbled wheel events from inside the dialog.
- A CSS-only pass-through is not enough when backdrop clicks must stay blocked; `pointer-events: none` would also re-enable unsafe background clicks.
- Keep the explicit routing narrow: attach backdrop wheel handling only in the specific screen state that needs background scrolling, and compute the target scroll position in a pure helper.
- Add a dialog-container wheel guard with `stopPropagation = True` and `preventDefault = False` so the dialog keeps native wheel/touchpad scrolling while backdrop routing still works outside the dialog.
- Let existing list load-more / fold logic observe the resulting viewport change instead of re-implementing pagination inside the modal code.

## Examples
- `src/Frontend.elm`: `groupTransactionsDialogMaskScrollPlan` clamps backdrop scroll routing for `#group-transactions-list`.
- `src/Frontend.elm`: `dialogContainerWheelBlockerAttribute` prevents bubbled wheel events from the spending dialog body from reaching the mask.
- `tests/FrontendTests.elm`: pure assertions around the backdrop scroll plan keep the routing seam testable without opaque `Cmd` inspection.

## Anti-Patterns
- Dropping backdrop pointer events entirely just to make wheel pass through; that also re-enables background clicks.
- Catching wheel on the backdrop without stopping it at the dialog container; nested scroll areas will look broken even if their scrollbars still drag.
- Duplicating load-more logic in the modal path instead of reusing the existing viewport observers.
