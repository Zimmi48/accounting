# Decisions Log

## Hicks & Vasquez: Negative Total Spending Fix

**Date:** 2026-05-05  
**Owner:** Hicks (implementation), Vasquez (testing & approval)  
**Artifact:** Spending validation semantics (frontend & backend)  
**Verdict:** APPROVED ✅

### Context

Frontend submission for spendings regressed after the multi-date spending refactor. The dialog guard only allowed `totalInt > 0`, which disabled submit for historically valid negative spendings. Backend validation in `src/Backend.elm` had the same strict-positive check.

### Decision

Restore signed-total support by treating spendings as valid when credits, debits, and the spending total all match the same non-zero amount, whether positive or negative. This matches older submit semantics, preserves compatibility with historical negative spendings, and keeps zero-total spendings invalid.

### Changes

- **Frontend:** `canSubmitSpending` in `src/Frontend.elm` now allows `totalInt /= 0` instead of `totalInt > 0`
- **Backend:** `isBalancedTransaction` and `validateSpendingTransactions` in `src/Backend.elm` updated to non-zero signed-total logic
- **Tests:** Added regression coverage to `tests/FrontendTests.elm` (frontend submit gate) and `tests/BackendTests.elm` (backend invariant)
- **Skills:** Updated `.squad/skills/spending-validation/SKILL.md` with corrected validation semantics
- **Mixed-sign coverage:** Preserved existing test coverage (total 100 with creditors [200, -100])
- **Zero-total constraint:** Maintained: zero-total spendings remain invalid

### Verification

✅ **Reproduced** both frontend and backend failures with focused Elm tests  
✅ **Frontend test:** Balanced dialog with total `-10.00` now submits  
✅ **Backend test:** `Amount -100` spending with matched credits/debits now survives validation  
✅ **Validation gates:**
   - elm-format src/ tests/ --yes ✅
   - ./check-codecs.sh ✅
   - lamdera make src/Frontend.elm --output=/dev/null ✅
   - lamdera make src/Backend.elm --output=/dev/null ✅
   - npm test (33 passing) ✅
   - lamdera live HTTP 200 ✅

### Rationale

The seam is cross-cutting; frontend and backend must agree on validation semantics or the app fails differently depending on where validation fires. The signed-total invariant (`credits == debits == total`) applies to both positive and negative spendings—the sign distinction is only on magnitude, not on the relationship.

---

## Vasquez Review: Hicks Ordering Revision

**Date:** 2026-04-27T16:22:00Z  
**Reviewer:** Vasquez  
**Artifact:** reverse-transaction-order (Hicks revision)  
**Verdict:** APPROVED ✅

### What Was Verified

#### Frontend consumer seam
- `groupTransactionsFromBackend` in `src/Frontend.elm` now contains `List.reverse responseTransactions` — the reversal is restored at the correct consumer boundary.
- `ListGroupTransactions` handler calls `groupTransactionsFromBackend` unchanged; the reversal is inside that helper.

#### Backend emission order (confirmed still ascending)
- `allTransactionsWithIds` (Backend.elm:1029–1059) uses three nested `Dict.foldr` calls with `++ acc` pattern.
- `Dict.foldr` visits keys highest-to-lowest; prepending current items onto the accumulator (which already holds newer-day items) builds oldest-first. Confirmed: backend emits ascending order.
- Frontend reversal at `ListGroupTransactions` boundary is necessary and correct.

#### Test regression quality
- Input `backendTransactions` is in ascending order: Apr 16 → Apr 17 → Apr 18 (idx=1) → Apr 18 (idx=2). This matches the actual backend emission order.
- Expected output is newest-first: Apr 18 (idx=2) → Apr 18 (idx=1) → Apr 17 → Apr 16.
- Same-day ordering is also exercised: two items on Apr 18 appear in reverse insertion order (idx=2 before idx=1), which is correct "most recently appended first" within a day.
- "Ignore other group" case covered.
- All 15 tests pass (2 new ordering tests added; 13 prior tests intact).

### Decision Recorded

- Hicks's revision satisfies the full rejection requirement list from the prior cycle.
- No further revision required.
- Status: Complete.

---

## Hicks: Fix transaction ordering

- Restored frontend-side reversal in `src/Frontend.elm` at the `ListGroupTransactions` consumer seam.
- Kept backend behavior unchanged.
- Replaced the prior weak ordering test with a regression in `tests/FrontendTests.elm` that feeds a realistic oldest-first backend response and asserts stored transactions are newest-first after consumption.
- Validation run: `elm-format`, both `lamdera make` targets, `npm test`, and `lamdera live --port=8002` with HTTP 200.
