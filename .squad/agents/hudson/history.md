# Project Context

## Core Context (Archived Sessions)
- ## Core Context
- ## 2026-04-27T16:02:33Z: Ordering Revision Rejection & Lockout

## Session: Export Diff Tool Completion (2026-04-28T14:46:16Z)
**Topic:** Export diff tool for pre/post migration JSON comparison

**Status:** ✅ Complete

**Deliverables:**
- `scripts/compare_exports.py` — semantic comparison script
- README.md — documentation updates

**Decision:** "Export diff normalization for migration review" approved and merged to decisions.md

**Validation:** Repo validation passed. Tool normalizes logical spendings, groups, person-name sets, and totals while ignoring storage-only churn.

**Outcome:** Addresses core challenge of noisy JSON diffs by enabling semantic comparison between legacy and current export formats.
## 2026-04-28: Group Transaction Diff Tool - Export Seam Coverage
**Event:** Initial implementation of per-group active-transaction comparison for export diff.

**Assignment:** Implement scripts/compare_exports.py with per-group comparison to catch regressions in group transaction listings (user-facing seam).

**Outcome:** First revision rejected by Vasquez for not replaying real `RequestGroupTransactions` seam semantics. Locked out and reassigned to Dallas for revision.

**Key finding:** Storage-level parity alone is not sufficient; must include active filtering, description composition, sign rendering, and ordering from real backend/frontend paths.

**Impact:** Established that export diff tool must compare the complete group-listing seam, not just aggregate storage facts.
