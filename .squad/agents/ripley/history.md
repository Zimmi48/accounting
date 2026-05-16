# Project Context

## Core Context (Archived Sessions)
- ## Core Context
- ## Migration Session: Evergreen Prep & Commit (2026-05-14T11:56:22Z)

## Learnings
- **Issue #52 pagination seam:** Keep group transaction pagination month-scoped, not row-scoped. `RequestGroupTransactions` now carries `{ group, before }`, and `ListGroupTransactions` returns `{ before, nextCursor, items }` so the frontend can append older months without guessing offsets.
- **Summary placement pattern:** Month summaries belong after that month's transactions; year summaries only appear when the loaded batch reaches the year boundary. This avoids rendering a full-year footer in the middle of a partially loaded year.
- **Migration safety for frontend lists:** For V33 -> V34, legacy listed transactions can be preserved by wrapping them as `GroupTransactionRow` items while resetting new pagination state (`groupTransactionsNextCursor = Nothing`, `groupTransactionsLoading = False`).
- **Key file paths:** `src/Types.elm` defines the pagination contract, `src/Backend.elm` builds month-bucket pages, `src/Frontend.elm` owns scroll-triggered loading, and `src/Evergreen/Migrate/V34.elm` handles the progressive-list migration.
- **User workflow preference:** When a change requires an Evergreen migration, Théo wants the implementation completed and committed first, then reviewed—no pre-commit review round.
- **Issue #53 theme seam:** Keep the theme itself in the query string, but encode page-local `Page` state in the URL fragment when a theme toggle rewrites the location. That preserves `Import` drafts, `Json` exports, and a `NotFound` sentinel across the `ToggleTheme -> UrlChanged` round-trip without adding frontend fields or Evergreen work.
- **Regression-test pattern:** For URL-backed frontend state, helper parsing tests are not enough; add round-trip coverage that goes through `pageUrl` and `routing` so the toggle-generated URL is forced back through the real route seam.
- **Key file paths:** `src/Frontend.elm` owns the theme/page URL contract and route hydration, while `tests/FrontendTests.elm` now covers the toggle round-trip for `Import`, `Json`, and `NotFound` pages.
- **Issue #51 dark-mode accent:** Green action surfaces in dark mode need their own contrast contract, not just a darker tint. Reusing the bright light-mode accent with dark text kept buttons and markers legible against the dark palette.
## Session 2026-05-16: Issue #53/#51 Resolution (Approved)
**Revision timestamp:** 2026-05-16T18:43:46Z  
**Approval:** Vasquez at 2026-05-16T18:43:00Z

Revised Hicks's #53 theme persistence to close state-loss regression while keeping implementation frontend-local and migration-free. Also addressed #51 dark-mode readability.

### #53 Fix
- Kept theme persistence URL-backed (`?theme=dark`)
- Widened URL contract to encode `Import` drafts, `Json` exports, `NotFound` in fragments
- Added proof-grade tests covering real `ToggleTheme -> UrlChanged` seam
- All stateful pages now round-trip correctly

### #51 Fix
- Raised dark-mode accent green from muddy to bright (matching light mode)
- Updated action text to black for proper contrast
- Locked palette contract with regression tests

**Validation:** All tests passing (80/80), both modules compile, HTTP 200 from lamdera live.

**Team note:** No shared-type, migration, or elm.json churn. This is the correct scope for both issues.

## Session 2026-05-17: URL Fragment Design Clarification (Ripley Review)

Addressed user question: "Why URL fragments (`draft`, `not-found`, `payload`) in #53? Are they overly broad?"

**Finding:** Fragments are **necessary**, not overly broad.

**Mechanism:** When `ToggleTheme` fires, it calls `Nav.replaceUrl` with a new URL from `pageUrl`. The browser navigates, triggering `UrlChanged`. The `routing` function must parse this new URL to reconstruct `Page`. Without fragments, page-local state (`Import String`, `Json (Maybe String)`) would be lost—the routing function would see only path+query and create empty state.

**Scope (minimal, not broad):**
- `draft=#draft=<json>` — carries unsaved Import content across toggle
- `payload=#payload=<json>` — carries prepared Json export across toggle
- `not-found=#not-found` — disambiguates NotFound (path="/") from Home (path="/") in URL
- Home — no fragment, no state to preserve

**Test proof:** `pageRoundTrip` in FrontendTests.elm validates the full cycle: `Page -> pageUrl -> routing -> Page` with fragments intact.

**Conclusion:** This is the correct design for preserving frontend-only state during URL-rewrites without Evergreen churn. The fragments are not wishful thinking—they're the seam where Page state lives during navigation.

## Session 2026-05-17: #53 Reassessment on Fragment Necessity (Ripley Review, User Correction)

**Objection from user:** "Fragment encoding is not necessary. The theme button is not accessible from secondary pages, so toggle cannot happen there."

**Reassessment finding:** User is **absolutely correct**.

**Analysis:**
- `themeButton` is defined once (line 2435-2448) and included only in Home page view (line 2754)
- NotFound, Json, Import pages render without the button (lines 2451-2544)
- `ToggleTheme` can only fire from Home; it cannot be triggered from secondary pages
- Fragments (`#draft`, `#payload`, `#not-found`) are therefore encoding state for a toggle that can never happen in practice

**Verdict on necessity:** Fragments are overengineering. The prior explanation correctly described the mechanism but incorrectly assumed the UI constraint was irrelevant. Elm's SPA model preserves page state in-memory during navigation naturally; fragments add complexity without solving a real problem today.

**If this were to change:** Adding theme toggle to secondary pages would require fragments. But that's a future decision, not current necessity.

**Key insight:** Defensive programming for hypothetical scenarios adds overhead. Cross-cutting concerns like URL state deserve explicit use-case justification, not "just in case" preventive measures.
