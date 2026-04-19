# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Full-stack group expense and accounting app with shared models, backend logic, and Elm UI.
- **Created:** 2026-04-20

## Learnings

- Joined to own full-stack recovery and compile-first revisions after prior authors were locked out on the spending/transaction split artifact.
- User directive: do not generate the Evergreen migration before Théo reviews the model changes.
- Compile-first split shape: `BackendModel` now keeps `spendings : Dict SpendingId Spending` plus dated `Day.transactions`, with `Spending.transactionIds` and `Transaction.spendingId` as the cross-reference seam.
- Phase 1 edit/delete contract lives in `src/Types.elm`, `src/Backend.elm`, `src/Frontend.elm`, and `src/Codecs.elm`; the frontend still submits one default transaction bucket using the dialog date and an empty secondary description.
- `RequestSpendingDetails` is the safe bridge for the old dialog: backend returns one editable bucket for singleton spendings and rejects multi-transaction spendings until the later UI pass.
- `2026-04-20T16:43:52Z`: Model-only spending/transaction split approved for user review
- `2026-04-21`: The rejected Phase 2 seam in `74261e3` lived in mirrored total checks, not the shared model shape: `src/Backend.elm` still required `credits == debits == total`, and `src/Frontend.elm` still blocked submit unless each side summed to `total`.
- `2026-04-21`: The recovery fix keeps `Spending.total` as the only amount-level invariant, while line items remain ID-free and still validate per-line date, group, and positive amount; validation stayed on `elm-format src/ --yes`, both `lamdera make` targets, and `lamdera live` returning HTTP 200 with no `src/Evergreen/` diff.
- `2026-04-26`: The spending dialog's line date pickers only show the today marker when each `TransactionLine.datePickerModel` is seeded with the real dialog-local `today`; `DatePicker.setToday` repairs existing models, but any line model re-created in `defaultTransactionLine` or `transactionLineFromSpendingTransaction` must also initialize from `today` (see `src/Frontend.elm`).
- `2026-04-26T15:55:20Z`: Diagnosed line picker today marker bug. The fix: seed all newly created date picker models (placeholder lines and loaded spending details) using `DatePicker.initWithToday today` and `DatePicker.setVisibleMonth` for month visibility. This ensures today's date marker displays correctly in all contexts.
- `2026-04-27`: Spending dialog default line dates must stay implicit in `TransactionLine.date : Maybe Date`, but submission must serialize them with the dialog's effective spending date and edit hydration must round-trip any transaction whose date matches the dialog spending date back to `Nothing` (`src/Frontend.elm`).
- `2026-04-27`: Import decode failures should reuse `SpendingError` across the Lamdera seam and surface through `FrontendModel.errorMessage`, so the import page and spending dialog both show visible user-facing errors instead of silently failing (`src/Backend.elm`, `src/Frontend.elm`, `src/Types.elm`).
- `2026-04-27`: User preference for the spending dialog is no automatic blank-row pruning: keep the virtual add row view-only, but once a debitor/creditor row becomes real in `src/Frontend.elm`, leave it in `AddSpendingDialogModel.credits` / `.debits` until the user explicitly removes it.
- `2026-04-27`: The auto-pruning seam lived entirely in `src/Frontend.elm`; removing it only required deleting `pruneBlank*` helpers and their update/hydration call sites, while leaving `AddDebitor` / `AddCreditor`, `shouldRenderVirtualTransactionLine`, and submit-time transaction derivation intact.
- `2026-04-27`: Exact transaction addressing now stays derived from append-only `Day.transactions` order; `src/Backend.elm` appends same-day writes and derives `TransactionId` slots on read, while `Transaction.spendingId` is the canonical persisted membership link across `src/Types.elm`, `src/Backend.elm`, and `src/Codecs.elm`.
- `2026-04-27`: When Théo deletes unapproved Evergreen artifacts, treat that as an active lockout on migration generation: keep compile/test recovery inside `src/Types.elm`, `src/Backend.elm`, `src/Codecs.elm`, `src/Frontend.elm`, and do not recreate `src/Evergreen/V26/*` until explicitly asked.
- `2026-04-27`: The validation gate for this append-only seam is `elm-format src/ tests/ --yes`, `./check-codecs.sh`, both `lamdera make` targets, `npm test`, and a successful `lamdera live` HTTP 200 check.

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
