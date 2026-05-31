# User Directive: Subtle transaction check marker (2026-05-15)

**By:** Théo Zimmermann

**What:** For the transaction checked marker, do not use the app's default bright green or a colored border; prefer a subtler single dot like the transaction-line marker in the spending dialog.

**Why:** User request — captured for team memory

**Status:** ✓ Captured for Hicks implementation

---

# Decision: Transaction check marker polish

**Timestamp:** 2026-05-15T11:30:00Z

**Agent:** Hicks

**Issue:** #32 (visual affordance polish)

## Decision

Use a dedicated muted green dot for checked transaction markers while keeping the surrounding button border neutral and the marker borderless.

## Why

The checked state should still read as distinct, but the default accent green and matching green border felt too loud for the transaction list. A smaller borderless dot removes the seam that regressed before and better matches the lighter-weight marker treatment used around transaction lines in the spending dialog. Aligns with user directive for subtler visual treatment.

## Implementation

- Frontend: dedicate muted green dot in `src/Frontend.elm` `transactionCheckIndicator` helper
- No border on surrounding button; neutral styling
- Borderless marker design matches spending dialog transaction-line marker pattern

## Status

⏸ Pending frontend regression coverage. See: Vasquez review (2026-05-15T11:32:00Z)

---

# Review: Vasquez — Issue #32 Hicks check marker revision

**Timestamp:** 2026-05-15T11:32:00Z

**Reviewer:** Vasquez (Tester)

**Topic:** Hicks's transaction check marker polish for Issue #32

## Verdict

**REJECT** — UI change is directionally correct, but regression coverage still misses the rendering seam.

## Findings

- **Condition 1:** ✓ Appears implemented in `src/Frontend.elm`: marker now owns its fill via `transactionCheckIndicator` instead of inherited color.
- **Condition 2:** ✓ Covered by `toggleGroupTransactionChecked` plus the targeted-row test.
- **Condition 3:** ✓ Covered by the composed backend refresh test that keeps clicked row checked while leaving untouched row alone.

## Why Still a Reject

- My acceptance note required frontend coverage proving the checked and unchecked marker render differently from the **view seam**, not just that a pure helper returns different states.
- Hicks added a `transactionCheckVisualState` test, but that only checks enum mapping from `Bool`; it does not guard the rendered marker/button attributes that regressed in the first place.

## Next Assignment

Assign next revision to **Dallas**. Remaining work: add explicit frontend regression coverage around rendered marker seam, then rerun existing validation gates.

**Status:** Awaiting Dallas assignment

---

# Decision: User Directive — Reload Migration Handling (2026-05-15T15:58:18Z)

**By:** Théo Zimmermann (via Copilot)

**What:** For this model-changing reload fix, delete the generated migration and do not regenerate or hand-fix it until the user explicitly asks after reviewing the code changes.

**Why:** User request — review-first workflow. Code changes must be approved before migrating types.

**Status:** ✓ Enforced throughout Newt → Hudson → Vasquez pipeline

---

# Decision: Paginated Refresh Depth (2026-05-15)

**Owner:** Newt

**Context:** Issue #52's incremental loading kept only one page on add/edit refresh, so deeper history views snapped back toward newer transactions.

**Decision:** Track the active group's loaded page count in frontend state and let `RequestGroupTransactions` ask the backend for that many pages on a reload, while scroll-driven load-more continues requesting a single additional page.

**Why:** The reload path should preserve the user's current history depth without changing the month-bucket pagination rules or the reverse-chronological rendering contract.

**Implementation Status:** Committed as 8224e1b, initially rejected for insufficient seam coverage, then approved in revised form as 06940a4

**Migration Note:** Deleted stale V34 migration artifacts per user directive; awaiting explicit user approval before regeneration

---

# Decision: Pure OperationSuccessful Refresh Plan Helper (2026-05-15)

**Owner:** Hudson

**Context:** Lamdera `Cmd` values are opaque in Elm tests, but the rejected revision needed proof at the real mutation-triggered reload seam rather than another helper-only page-depth assertion.

**Decision:** Extract the `OperationSuccessful` home-page refresh logic in `src/Frontend.elm` into a pure `operationSuccessfulRefreshPlan` helper that returns the updated frontend state plus the `ToBackend` messages to emit.

**Why:** This keeps runtime behavior mechanical while making the review seam directly testable. The regression test can now load multiple pages, replay the exact refresh request after `OperationSuccessful`, and verify the refreshed list still includes the older month with correct chronology and summary placement.

**Implementation Status:** Committed as 06940a4, approved by Vasquez

---

# Decision: Normalize Paged Group Transactions with Explicit Descending Row Sort (2026-05-15)

**Owner:** Dallas

**Context:** Issue #52 kept month/year summaries above their blocks by normalizing merged `GroupTransactionListItem` pages on the frontend. That normalization preserved header placement, but it also preserved the backend's per-month row order, which is oldest-first inside each month.

**Decision:** When `src/Frontend.elm` rebuilds the grouped transaction list, it must sort:
- years descending
- months descending within each year
- transaction rows descending by `(year, month, day, transactionId.index)`

This keeps summary rows above each block while restoring strict reverse-chronological transaction order.

**Consequences:**
- Later year-boundary pages can still hoist a year summary above already-loaded newer months.
- Ordering no longer depends on how backend pages happened to arrive before normalization.
- Regression coverage belongs on `Frontend.groupTransactionsFromBackend` with realistic backend-ordered fixtures, including same-day index ordering.

**Status:** Under review

---

# Approval: Deep-Page Refresh Proof (2026-05-15T16:17:14Z)

**By:** Vasquez

**What:** Commit 06940a4 is approved

**Why:**
- `src/Frontend.elm` now routes `OperationSuccessful` through the pure `operationSuccessfulRefreshPlan` helper, and `updateFromBackend` consumes that helper directly.
- `tests/BackendTests.elm` finally proves the real seam: two pages are loaded, the remembered depth is replayed as `RequestGroupTransactions { before = Nothing, pages = 2 }`, and the refreshed merged list still shows the older month with reverse chronology and summary headers intact.
- The stale migration remains unregenerated as requested: there is no `src/Evergreen/Migrate/V34.elm` or `src/Evergreen/V34/Types.elm`.

**Validation:**
- ✅ `elm-format --validate src/ tests/`
- ✅ `lamdera make src/Frontend.elm --output=/dev/null`
- ✅ `lamdera make src/Backend.elm --output=/dev/null`
- ✅ `npm test` (59/59)
- ✅ `lamdera live` with localhost HTTP 200

**Status:** Ready for merge


---

# Decision: V35 transaction-list migration follow-up (2026-05-16T12:58:49Z)

**By:** Bishop

**What:** Treat Evergreen V35 as a message-only migration. Commit Lamdera-generated `src/Evergreen/V35/Types.elm` and `src/Evergreen/Migrate/V35.elm` first, then hand-fix `src/Evergreen/Migrate/V35.elm` by removing the unreachable generated `Unimplemented` fallback and keeping all V34 constructors as direct carry-over mappings.

**Context:** The approved transaction-list work added `ToggleGroupTransactionMonthFold` and `GroupTransactionsViewportChecked` to `FrontendMsg`, but it did not change `FrontendModel`, `ToBackend`, `ToFrontend`, or backend storage.

**Why:** Old persisted/client-inflight data can only contain V34 constructors, so introducing the new fold/viewport constructors does not require resets or synthetic migration targets. The real risk is leaving the generated fallback in place and shipping an incomplete Evergreen file.

**Validation:**
- ✅ `lamdera check --force`
- ✅ `lamdera make src/Frontend.elm --output=/dev/null`
- ✅ `lamdera make src/Backend.elm --output=/dev/null`
- ✅ `npm test`
- ✅ `lamdera live --port=8002` with HTTP 200

**Commits:**
- 8d14bfe: Generated artifacts
- cf3bf3a: Manual follow-up fix

**Status:** Completed

---

# Decision: Dialog Mask Wheel Routing for Group Transactions (Dallas, 2026-05-31)

**Status:** Proposed and implemented locally.

**Decision:** Keep dialog masks modal for clicks, but route wheel scrolling on the mask into the grouped transaction viewport instead of dropping mask pointer-events.

**Why:** Progressive loading moved the transaction history into its own scroll container. Letting the mask go transparent to pointer events would re-enable unsafe background clicks; routing `deltaY` through `Browser.Dom.getViewportOf` / `setViewportOf` restores the old "scroll the list behind the dialog" behavior while preserving dialog safety, month/year grouping, progressive pagination, and fold state.

**Implementation details:**
- `src/Types.elm`: add `DialogMaskWheelScrolled Float`
- `src/Frontend.elm`: attach a mask `wheel` handler only when the home transaction list is active, compute a pure `groupTransactionsDialogMaskScrollPlan`, and scroll `#group-transactions-list` programmatically
- `tests/FrontendTests.elm`: cover the routing/clamp seam with the pure plan helper rather than opaque `Cmd` assertions.

---

# Decision: Dialog + Grouped Transaction Regression Coverage (Hockney, 2026-05-31)

**Date:** 2026-05-31

**Requested by:** Team coordination with Dallas's dialog scroll fix

## Observation

The frontend test suite can independently cover the message/planning contract for progressive transaction loading with an open dialog:

- bottom-of-list load-more planning still emits `RequestGroupTransactions`
- month-fold toggles still request a viewport recheck when a dialog is open

## Regression Assertions

Exact assertions Dallas's implementation should make testable:

1. Opening a dialog must not remove or replace the `groupTransactionsViewportId` scroll container.
2. The dialog overlay/mask must not block wheel or touch scrolling intended for the transaction list behind it.
3. Once a scroll occurs with a dialog open, the same progressive-loading path must run as without a dialog: existing month/year summaries stay ordered, and bottom-of-list scrolling can still request the next page.

**Status:** Implemented in `tests/FrontendTests.elm` with pure plan helpers and approved test cases.
