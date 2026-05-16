# Project Context

## Archive (2 older sessions condensed)
See decisions.md for historical context.
## Session 2026-05-16: Issue #53/#51 Review Workflow (Approved Ripley Revision)
**Review gates:** 2026-05-16T18:32:20Z (reject Hicks), 2026-05-16T18:43:00Z (approve Ripley)

Performed two critical review functions for the theme persistence and dark-mode readability work:

1. **#53 Rejection:** Identified state-loss regression in Hicks's toggle seam where `Nav.replaceUrl` was losing state on stateful pages. Requested tighter coverage and reassigned to Ripley.

2. **#53/#51 Approval:** Approved Ripley's revision that preserved theme persistence via URL fragments and fixed dark-mode green readability by raising accent and using black text.

**Validation:** 80/80 tests passing, both Frontend/Backend compile, HTTP 200 from lamdera live.

**Team impact:** This closes both #53 and #51 with frontend-local changes requiring no migrations or shared-type churn.

## Learnings
- 2026-05-17T11:50:00Z: Minimal follow-ups for issue #53 should keep reload persistence scoped to `src/Frontend.elm`'s theme bootstrap/query seam (`init`, `UrlChanged`, `ToggleTheme`) and avoid widening the URL contract to serialize unrelated page-local state like `Import` drafts, `Json` exports, or `NotFound` markers. Review `tests/FrontendTests.elm` for issue-split discipline too: #53 coverage should stay on theme reload/query rewriting, while dark-palette assertions belong to #51. Validation reference for review work remains `npm test`, both `lamdera make` targets, and `lamdera live` with HTTP 200.
- 2026-05-17T11:52:00Z: When reassessing a "minimalized" follow-up, review the full candidate diff against the parent commit, not just the latest cleanup patch. In this repo that catches carried-forward scope creep such as `tests/FrontendTests.elm` still bundling the dark-palette assertion (`describe "theme palette"`) even after the fragment/state round-trip tests were removed from #53.
- 2026-05-17T11:57:00Z: The minimal acceptable #53 patch in this repo is query-only theme persistence: `init` and `UrlChanged` hydrate from `themeFromUrl`, internal navigation preserves the current theme via `themeFromUrlOr` and `urlStringWithTheme`, and `ToggleTheme` rewrites only `pageUrl theme model.page`. Any fragment encoding for `Import` drafts, `Json` payloads, or `NotFound` is broader than the contract, and the narrow proof set is 76 passing tests plus successful `lamdera make` for both entrypoints and `lamdera live` returning HTTP 200.
