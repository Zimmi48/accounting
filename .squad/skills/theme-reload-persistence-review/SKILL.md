---
name: "theme-reload-persistence-review"
description: "How to review frontend theme persistence fixes without mistaking route-state survival for real reload persistence"
domain: "review"
confidence: "medium"
source: "earned"
---

## Context
Use this when a Lamdera/Elm UI preference such as light/dark mode is supposed to survive browser reloads. These fixes often look done because the toggle works and internal navigation keeps the same in-memory model, but reload persistence is a different seam.

## Patterns
- Inspect `init` first. If it still hardcodes the default preference, reload persistence is not fixed unless there is an explicit hydration path.
- Distinguish **internal navigation persistence** from **reload persistence**. `UrlClicked`/`UrlChanged` preserving `model.theme` only proves route changes do not clobber state.
- Require evidence for the browser boundary: local storage, flags, ports, or another bootstrap mechanism that can repopulate the preference before first render.
- For this repo, prefer a migration-free fix when the preference already exists in `FrontendModel`; do not approve unnecessary Evergreen churn just to persist a browser-local choice.
- Test coverage must prove both seams: reload/bootstrap restores the chosen theme, and internal navigation still leaves it alone.

## Examples
- `src/Frontend.elm:init` currently seeds `theme = LightMode`, so any reviewed fix must change the bootstrap path or it will still reset on refresh.
- `src/Frontend.elm:ToggleTheme` currently only flips in-memory state, which is sufficient for same-session routing but not for a full reload.
- `tests/FrontendTests.elm` should gain theme-focused regression coverage; unrelated transaction-list tests do not prove this issue.

## Anti-Patterns
- Approving a fix because the toggle button label changes during one session.
- Treating route navigation as proof of reload persistence.
- Adding migration work when the issue is really a browser bootstrap/storage seam.
