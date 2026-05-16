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
- When rewriting URLs for theme changes, preserve any page-local state encoded outside the path contract; a helper built only from `Page -> path` is unsafe if `Page` also carries in-memory draft/export state.
- If the current `Page` constructor carries frontend-only draft/export state, encode that state into the rewritten URL itself (for example in the fragment) before `Nav.replaceUrl`, then hydrate it back in `routing`.

## Examples
- `src/Frontend.elm`: `themeFromUrl`, `themeFromUrlOr`, `urlStringWithTheme`, `pageUrl`
- `tests/FrontendTests.elm`: theme bootstrap and query-rewrite regression tests
- `tests/FrontendTests.elm`: round-trip `pageUrl -> routing` tests for `Import`, `Json`, and `NotFound` prove the real toggle seam.
- `src/Frontend.elm`: `pageUrl` is only safe when the current `Page` constructor carries no extra state that would be lost on the resulting `UrlChanged`.

## Anti-Patterns
- Do not reconstruct a theme toggle URL from route path alone on pages like `Import String`, `Json (Maybe String)`, or `NotFound`; the follow-up `UrlChanged` will wipe draft/export/error state or silently navigate elsewhere.
- Do not add shared/frontend model fields just to persist a browser-local theme when URL state is enough.
- Do not treat in-memory `ToggleTheme` state as proof of reload persistence.
- Do not use `pushUrl` for theme flips unless product explicitly wants back-button history per theme change.
