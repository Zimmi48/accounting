# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Full-stack group expense and accounting app with shared models, backend logic, and Elm UI.
- **Created:** 2026-04-20

## Learnings

- 2026-05-15: Paginated group-transaction refreshes now track `FrontendModel.groupTransactionsLoadedPages` in `src/Types.elm` / `src/Frontend.elm`; initial loads and refreshes request that many pages at once through `RequestGroupTransactions.pages`, while scroll-driven load-more still requests one page and `ListGroupTransactions.pagesLoaded` reports how much depth was actually reloaded.
- 2026-05-15: Issue #32 persists transaction reconciliation as `Transaction.checked` across `src/Types.elm`, `src/Backend.elm`, `src/Frontend.elm`, `src/Codecs.elm`, and `src/Evergreen/V33/*`; `RequestGroupTransactions` / `ListGroupTransactions` now carry the flag for the lightweight list dot, unchanged rows keep their checked state through `reconcileSpendingTransactions`, and new or migrated rows default to `False`.
- 2026-05-15: The #32 click path still toggles through `ToggleTransactionChecked` / `ToggleTransactionCheckedRequest` and the backend list refresh, but the visible regression was in `src/Frontend.elm`: the raw SVG dot did not show the checked-state color change reliably, so the repair uses an elm-ui text glyph for the dot and keeps a frontend regression in `tests/FrontendTests.elm`.
- 2026-04-29: The spending lifecycle seam in `tests/BackendTests.elm` should validate `recomputedTotalsSnapshot` exactly for active rows, but stored redundant totals after edit/delete may only guarantee that stale amounts are missing-or-zero rather than structurally equal; pair those numeric invariants with the existing list/details visibility test and keep validation on `elm-format src/ tests/ --yes`, both `lamdera make` targets, `npm test`, and `lamdera live --port=8123` returning HTTP 200.
- 2026-05-15: Adding a persisted boolean directly to `Transaction` is a storage-shape change, not just UI wiring: the live model stores `Day.transactions : Array Transaction` in `BackendModel.groups` (`src/Types.elm`, mirrored in `src/Evergreen/V31/Types.elm`) and export/import serialization hard-codes that record in `src/Codecs.elm`, so a new `checked` field would require a Lamdera Evergreen migration plus codec/schema versioning.

## Core Context

### Newt's Role
- Full-stack Elm/Lamdera developer with deep context on spending/transaction split architecture
- Primary owner of cross-layer model/backend/frontend integration work
- Expertise: append-only transaction ID seaming, codec field-order discipline, Evergreen migration patterns

### Recent Completions (2026-04-27 to 2026-05-15)
1. **Line Picker Today Marker (2026-04-26):** Fixed date picker initialization to properly display today marker in spending dialog
2. **Remove Auto Pruning (2026-04-27):** Eliminated blank-row auto-pruning, requiring explicit user deletion
3. **Fix Reported Issues (2026-04-27):** Routed import errors to UI, fixed submission validation, preserved spending-date edit hydration
4. **Lifecycle Invariants (2026-04-29):** Revised lifecycle tests to validate total-computation without pinning cleanup state
5. **Transaction Reconciliation Toggle (2026-05-15):** Implemented lightweight list-only toggle flag with transaction-local `checked : Bool`, preserved reconciliation state on unchanged spending edits

### Validation Pattern
All work validated against: `elm-format src/ tests/ --yes`, `lamdera make` (Frontend + Backend), `npm test`, `lamdera live --port=8123` HTTP 200 check. Evergreen migrations only when required; pre-existing data backwards-compatible.

### Key Architecture Notes
- Backend stores `Day.transactions : Array Transaction` with append-only ID scheme
- Frontend submission default-dates implicit transactions, then submits to backend
- Spending edits preserve transaction metadata (`checked` flag, etc.) on logically unchanged rows
- Codec defaults new fields to maintain backwards compatibility with exported/imported data

## Session Archive (Consolidated 2026-04-20 to 2026-04-29)

## 2026-04-27T10:37:26Z: Remove Auto Pruning Session

- **Spawned:** Newt (Full-Stack Dev) to remove automatic blank-row pruning
- **Request:** Remove `pruneBlank*` functions and call sites entirely; no automatic pruning, preserve blank rows until user manually deletes
- **Fixes Applied:**
  - Removed `pruneBlankTransactionLines` and `pruneBlankSpendingDialogLines` from `src/Frontend.elm`
  - Removed all auto-pruning call sites from spending-dialog updates, spending-date default propagation, `SetToday`, and spending-details hydration
  - Kept `AddDebitor` / `AddCreditor`, `shouldRenderVirtualTransactionLine`, and submit-time transaction derivation unchanged
  - Virtual trailing row continues to render when appropriate for add affordance
- **Decision:** Merged to decisions.md (2026-04-27 "Remove Auto Pruning")
- **Validation:** Compiles; development server HTTP 200; no Evergreen migrations
- **Status:** Completed

## 2026-04-21: Phase 2 Contract Correction Verdict

- **Session timestamp:** 2026-04-21T06:49:24Z
- **Status:** Rejected — commit `50629e3` dropped the spending-level invariant entirely
- **Correction:** Hudson's commit `b7d0444` restored invariant in `validateSpendingTransactions`
- **Outcome:** Team stack approved; Newt's work rejected but contributed to understanding
- **Next phase:** Await Théo's data model review and Evergreen migration planning

## 2026-04-26T15:55:20Z: Line Picker Today Marker Session

- **Spawned:** Newt (Full-Stack Dev) to investigate missing today marker in line date pickers
- **Root Cause:** Line picker models created in `defaultTransactionLine` and `transactionLineFromSpendingTransaction` were not initialized with `today` via `DatePicker.initWithToday`
- **Fix Applied:** Applied `DatePicker.initWithToday today` to all new line picker models, plus `DatePicker.setVisibleMonth` for calendar month visibility
- **Validation:** Compiles; development server HTTP 200; no Evergreen migrations
- **Status:** Completed

## 2026-04-27T07:20:09Z: Fix Reported Issues Session

- **Spawned:** Newt (Full-Stack Dev) to implement three reported fixes
- **Request:** (1) Ignore transaction dates for submission validation; use default for Nothing. (2) Round-trip edit hydration: treat transactions matching spending date as default (Nothing). (3) Route import errors to UI.
- **Fixes Applied:**
  - Submission validation: Accepts default-date lines, validates group/amount only (`src/Frontend.elm`)
  - Edit hydration: Preserves spending date, hydrates matching transactions back to Nothing (`src/Frontend.elm`, `src/Backend.elm`)
  - Import errors: Routes decode failures through `SpendingError`, surfaces in `FrontendModel.errorMessage` (`src/Backend.elm`, `src/Frontend.elm`, `src/Types.elm`)
- **Decision:** Merged to decisions.md (2026-04-27T07:20:09Z)
- **Validation:** Compiles; development server HTTP 200; no Evergreen migrations
- **Status:** Completed

## 2026-04-27T11:47:00Z: Backend Revision Assignment

**Event:** Reassigned to complete backend/model refactor artifact.

**Context:** Bishop's refactor rejected due to incomplete `src/Evergreen/Migrate/V26.elm` (contains Unimplemented placeholders risking data loss).

**Task:** Complete backend revision with full data-preserving migration implementation.

**Bishop Status:** Locked out for this cycle.

**Related Tests:** Vasquez's 13-test suite now available for validation via `npm test`.

## 2026-04-27T12:04:51Z: Backend Revision Rejection & Lock

**Event:** Newt's replacement revision rejected by Vasquez. Newt locked out for this artifact.

**Verdict:** Reject

**What Passed:**
- Append-only slot logic internally correct in `src/Backend.elm`
- Same-day inserts append; transaction IDs derived from day-list position
- Spending membership recovered via `transaction.spendingId` instead of stored `Spending.transactionIds`
- All validation gates: `elm-format --validate src/ tests/`, `./check-codecs.sh`, both `lamdera make` targets, `npm test`, `lamdera live --port=8123` → HTTP 200
- No Evergreen files regenerated

**Why It Still Fails:**
- Persisted `Spending` and `Transaction` codec shapes changed:
  - Removes `BackendModel.nextSpendingId`
  - Removes `Spending.transactionIds`
  - Replaces `Transaction.id : TransactionId` with top-level year/month/day
- Breaking change for existing Lamdera state and exported JSON
- Under no-migration directive, cannot accept revision without Evergreen support

**Current Status:** Locked out for this artifact in current revision cycle.

**Reassignment:** Dallas assigned to next backend/model revision with data-migration constraints.

## 2026-04-29T07:25:19Z: Lifecycle Invariants Revision (Background)

- **Task:** Revise disputed lifecycle tests per user directive (Théo: keep validation but don't pin cleanup leak)
- **Context:** User requested removing disputed tests while preserving total-computation validation coverage
- **Solution:** Narrowed assertions to three layers:
  1. Exact `recomputedTotalsSnapshot` for active rows (what users see)
  2. Stored aggregate numeric invariants (active amounts land in right scope)
  3. Stale amounts must be zero or missing (structure not required)
- **Validation:** `npm test` passed; no Evergreen migrations
- **Decision merged:** Lifecycle Total Invariants (2026-04-29)
- **Status:** Completed; ready for merge review

## 2026-05-15T10:41:38Z: Transaction Reconciliation Toggle Session (Issue #32)

- **Spawned:** Newt (Full-Stack Dev) to implement lightweight reconciliation marker
- **Request:** Persist transaction-local `checked : Bool` for reconciliation toggle, list-only UI affordance, spending-edit contract unchanged
- **Fixes Applied:**
  - Added `checked : Bool` field to `Transaction` in `src/Types.elm`
  - Backend: New transactions default `checked = False`, toggle path via `ToggleTransactionChecked`
  - Frontend: List UI renders dot indicator, checkbox toggle in `ListGroupTransactions` view
  - Codec: `src/Codecs.elm` defaults new field to `False` for backwards compatibility
  - Evergreen V33: Migration preserves existing transactions at `checked = False`
  - Spending edit: Unchanged rows retain their `checked` state through `reconcileSpendingTransactions`; new rows default unchecked
- **Test Coverage:** Updated `tests/BackendTests.elm`, `tests/FrontendTests.elm`, `tests/CodecsTests.elm`, `tests/MigrationTests.elm`
- **Decision:** Merged to decisions.md (2026-05-15 "Transaction Checked Flag")
- **Validation:** All gates passed: `elm-format`, `lamdera make` (Frontend + Backend), `npm test`, HTTP 200, no unintended Evergreen regenerations
- **Status:** Completed; commit c98c59d approved

## 2026-05-15T11:17:55Z: Issue #32 Repair Follow-up — Toggle Dot Visual Regression (Completed)

- **Spawned:** Newt (Full-Stack Dev) to repair visual affordance for transaction toggle
- **Reviewer:** Vasquez (Tester)
- **Context:** Data flow intact from prior decision (#32 Toggle Flag). Regression: SVG dot not visually reflecting state change due to `currentColor` inheritance failure.
- **Repair Applied:**
  - Replaced raw embedded SVG with elm-ui text glyph in `src/Frontend.elm`
  - Rendered checked/unchecked states with distinct visual indicators
  - Added regression test coverage: checked vs unchecked render observably different, toggled row stays visibly toggled after backend refresh
- **Validation:** All gates passed: `elm-format`, `lamdera make` (Frontend + Backend), `npm test`, HTTP 200
- **Decision:** Merged to decisions.md (2026-05-15 "Transaction Toggle Dot Visual Repair")
- **Status:** Approved; commit 9c81ea4 approved by Vasquez
