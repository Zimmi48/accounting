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
- In minimal follow-ups, reject fixes that widen the URL contract just to preserve unrelated page-local state; theme persistence is the query/bootstrap seam, not an excuse to serialize every page variant.
- Keep tests aligned with the issue split: #53 should cover theme persistence behavior, while separate palette/readability regressions belong to their own issue/commit.
- Review the **full candidate diff against its parent commit**, not only the latest cleanup hunk; stray coupled tests can survive even after the implementation is narrowed.

## Examples
- A good fix in this repo wires `src/Frontend.elm:init` and `UrlChanged` through `themeFromUrl`, so reloading `/json?theme=dark` restores `DarkMode`.
- `src/Frontend.elm:ToggleTheme` should rewrite the browser URL (for example via `pageUrl`) so the next reload has something to hydrate from.
- `tests/FrontendTests.elm` should gain theme-focused regression coverage; unrelated palette/readability checks or transaction-list tests do not prove this issue.

## Anti-Patterns
- Approving a fix because the toggle button label changes during one session.
- Treating route navigation as proof of reload persistence.
- Adding migration work when the issue is really a browser bootstrap/storage seam.
- Letting a "minimal" patch keep broad fragment/state round-trips or unrelated regression tests that should have been left out.
- Looking only at the final cleanup diff and missing that the overall candidate still introduces unrelated assertions such as dark-palette checks.
