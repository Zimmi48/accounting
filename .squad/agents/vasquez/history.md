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
