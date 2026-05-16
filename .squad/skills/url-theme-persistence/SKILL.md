---
name: "url-theme-persistence"
description: "Persist a frontend-only UI theme across reloads by treating it as URL state"
domain: "frontend-state"
confidence: "high"
source: "earned"
---

## Context
Use this when a Lamdera/Elm UI preference such as light/dark mode must survive browser reloads, but the change should stay migration-free and frontend-local.

## Patterns
- Hydrate the preference in `init` from the incoming `Url.Url` instead of hardcoding a default every time.
- Keep the route path as the source of page selection; use a small query parameter like `?theme=dark` only for the UI preference.
- On `UrlChanged`, re-read the query so reloads, pasted URLs, and browser navigation all restore the same theme.
- On toggle, prefer `Nav.replaceUrl` over `pushUrl` so switching theme does not spam browser history.
- When handling internal navigation, preserve the current theme unless the clicked URL explicitly includes its own theme query.
- Extract pure helpers for query parsing and URL rewriting so tests can prove the reload seam without browser ports or JS.
- Keep the persistence scope narrow: only encode the UI preference itself unless the control can actually fire from a page whose state would otherwise be lost.
- If navigation already preserves a page's in-memory state, do not promote unrelated draft/export/error state into the URL just to support theme reloads.

## Examples
- `src/Frontend.elm`: `themeFromUrl`, `themeFromUrlOr`, `urlStringWithTheme`, `pageUrl`
- `tests/FrontendTests.elm`: theme bootstrap and query-rewrite regression tests
- `src/Frontend.elm`: `ToggleTheme` can stay path-based when the toggle button only appears on `Home`
- `src/Frontend.elm`: `UrlClicked` still threads the active `theme` query onto internal links so navigation keeps the chosen palette

## Anti-Patterns
- Do not encode unrelated page-local state into fragments or queries when the persistence requirement is only "reload keeps the current theme".
- Do not add shared/frontend model fields just to persist a browser-local theme when URL state is enough.
- Do not treat in-memory `ToggleTheme` state as proof of reload persistence.
- Do not use `pushUrl` for theme flips unless product explicitly wants back-button history per theme change.
