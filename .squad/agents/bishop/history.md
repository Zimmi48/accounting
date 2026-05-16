# Project Context

## Core Context (Archived Sessions)
- ## Core Context
- ## Summarized Context (2026-04-27 through 2026-04-29)

## 2026-05-05T19:49:26Z: Mixed-sign Spending Regression Fix (Background)
- **Task:** Fix backend regression where validation rejected balanced mixed-sign creditor amounts
- **Diagnosis:** `normalizeSpendingTransactions` and `isBalancedTransaction` in `src/Backend.elm` were incorrectly stripping non-zero negative amounts from individual transaction lines
- **Fix:** Preserve signed amounts through normalization; only drop rows that sum to exactly zero after merging by (date, secondaryDescription) bucket
- **Deliverables:**
  - Modified `src/Backend.elm` to keep non-zero signed transaction lines
  - Added regression test in `tests/BackendTests.elm` with mixed-sign scenario (total 100, creditors [200, -100])
- **Validation:** elm-format, check-codecs.sh, both lamdera make targets, npm test, lamdera live HTTP 200
- **Approval:** Vasquez (Tester) reproduced regression, verified fix, and approved for merge
- **Decision merged:** Mixed-sign spending validation (2026-05-05)
- **Status:** Completed; ready for merge
## 2026-05-15T08:04:13Z: Spending Edit Preservation Fix (Background)
- **Task:** Fix issue #49 — preserve unchanged spending rows during edit operations
- **Problem:** Backend spending edit flow marked every prior transaction `Replaced` and appended a fully fresh spending, even when rows were logically unchanged. This hid stable history and violated the intent of stable row preservation.
- **Root Cause:** `updateSpending` handler in `src/Backend.elm` lacked logical row identity matching; replaced all rows regardless of content changes
- **Solution:** Implement reconciliation by logical row identity `(date, secondaryDescription, group, side, amount)` before replacing:
  - Keep matched rows active; update their `spendingId` to attach to replacement spending
  - Refresh preserved rows with new spending-wide metadata (`groupMembersKey`, `groupMembers`)
  - Mark only unmatched old rows `Replaced`; append only unmatched new rows
- **Deliverables:**
  - Backend reconciliation logic in `src/Backend.elm`
  - Test coverage in `tests/BackendTests.elm` verifying preservation
  - Skill documentation: `.squad/skills/spending-edit-preservation/SKILL.md`
- **Validation:** elm-format, lamdera make src/Frontend.elm, lamdera make src/Backend.elm, npm test, lamdera live HTTP 200
- **Status:** ✅ Completed; commit 8edf105 approved for merge
- **Decision merged:** Spending edit transaction preservation (2026-05-15)

### 2026-05-15T16:43:52Z: Late-Arriving Year Header Seam — COMPLETED ✅

- **Task:** Fix the seam where an older year first appears on page 2 without rendering its year header line.
- **Root Cause:** Paginated group transaction list could introduce an older year on page 2 without emitting the corresponding year summary header.
- **Solution:** Emit year summary for each visible year when a response spans multiple years:
  - Backend carries year totals on every month slice
  - Emits year header whenever page spans multiple years or reaches visible end of year
  - Frontend merge already hoists late-arriving headers (no frontend changes needed)
- **Deliverables:**
  - Backend emission logic in `src/Backend.elm`
  - Test regression in `tests/BackendTests.elm` covering exact page-2 2025→2024 shape
- **Validation:** elm-format ✅, lamdera make src/Frontend.elm ✅, lamdera make src/Backend.elm ✅, npm test ✅, lamdera live HTTP 200 ✅
- **Status:** ✅ Completed; commit d5f7f8a approved and ready for merge
- **Reviewer:** Vasquez approved

### 2026-05-16T12:58:49Z: V35 FrontendMsg-Only Migration — COMPLETED ✅

- **Task:** Implement Evergreen V35 migration for transaction-list month folding and viewport rechecks.
- **Context:** Approved transaction-list work added `ToggleGroupTransactionMonthFold` and `GroupTransactionsViewportChecked` to `FrontendMsg`, but no changes to `FrontendModel`, `ToBackend`, `ToFrontend`, or backend storage.
- **Decision:** Treat V35 as a message-only migration. Lamdera-generated `src/Evergreen/V35/Types.elm` and `src/Evergreen/Migrate/V35.elm` first, then hand-fix `src/Evergreen/Migrate/V35.elm` by removing the unreachable generated `Unimplemented` fallback and keeping all V34 constructors as direct carry-over mappings.
- **Why:** Old persisted/client-inflight data can only contain V34 constructors, so the new fold/viewport constructors don't require resets or synthetic migration targets. The real risk is leaving the generated fallback in place and shipping an incomplete Evergreen file.
- **Deliverables:**
  - `src/Evergreen/V35/Types.elm` (Lamdera-generated)
  - `src/Evergreen/Migrate/V35.elm` (Lamdera-generated, hand-fixed)
  - Test updates in `tests/MigrationTests.elm` and `tests/CodecsTests.elm`
- **Validation:** 
  - ✅ `lamdera check --force`
  - ✅ `lamdera make src/Frontend.elm --output=/dev/null`
  - ✅ `lamdera make src/Backend.elm --output=/dev/null`
  - ✅ `npm test`
  - ✅ `lamdera live --port=8002` HTTP 200
- **Commits:**
  - 8d14bfe: Lamdera-generated V35 artifacts
  - cf3bf3a: Manual follow-up fix removing generated fallback
- **Status:** ✅ Completed; ready for merge
