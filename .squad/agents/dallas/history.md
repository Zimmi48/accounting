# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Full-stack group expense and accounting app with shared models, backend logic, and Elm UI.
- **Created:** 2026-04-20

## Core Context

**One-sided transaction model:** Transactions are one-sided line items per group/side; spendings own the invariant that total credits = total debits = spending total. Each transaction line owns its (year, month, day) and optional secondary description.

**Storage & ID addressing:** Day storage is `Array Transaction` (append-only); `TransactionId` is `{ year, month, day, index }` (now includes groupId for group-owned storage). `Spending.transactionIds` stores the list of transaction ids for direct lookup (no whole-model scan/filter).

**Validation gates:** `elm-format src/ tests/ --yes`, `./check-codecs.sh`, both `lamdera make` targets, `npm test`, `lamdera live` → HTTP 200.

**Key approvals:**
- Phase 2 contract (spending invariant + transaction dates): ✅ Approved 2026-04-21
- Spending.transactionIds restoration (direct lookup replaces whole-model scan): ✅ Approved 2026-04-27
- Transaction ordering (frontend reversal at seam): ✅ Approved 2026-04-27
- Model port boundary (types + codecs, defer per-group machinery): ✅ Approved 2026-05-14

## Historical Work Summary (Consolidated from 2026-04-27 to 2026-05-03)

**Spending.transactionIds Restoration (2026-04-27):** Restored direct lookup using stored transaction ids instead of whole-model scan/filter. Updated Types.elm, Codecs.elm, and Backend.elm. All validation gates passed. Approved by Vasquez.

**Cleanup Split Verdict (2026-04-27):** Dual-commit pass delivered two separate revisions: (A) cleanup-pending-transaction approved, (B) reverse-transaction-order rejected pending retest. Reassigned ordering to Hicks; Dallas locked from ordering artifact for cycle.

**Evergreen V26 Migration (2026-04-28):** Participated in migration planning and testing. Chronological rebuild strategy preserved backend history exactly. Durable ID mapping validated. All repo checks green. Ready for deployment.

**Export Diff Tool (2026-04-28):** Revised scripts/compare_exports.py to replay actual RequestGroupTransactions seam instead of storage-only comparison. Legacy exports derived from active spendings; current exports use backend filter. Approved after code inspection and seam assertions.

**Lifecycle Total & Regression Testing (2026-04-29):** Comprehensive test coverage for spending total recomputation across add/edit/delete. Identified and fixed aggregation bugs. Per-transaction lifecycle now validated. Tests cover full flow.

**Group Years Refactor (2026-05-02 to 2026-05-03):** Transitioned storage to per-group ownership. Person ID keying simplified. Staged three-phase approval: (1) grouping refactor, (2) per-group owner migration, (3) ID-keyed lookup consistency. All tests passing; migration safety validated.

**Negative Spending Support (2026-05-05):** Frontend and Backend validation gates restored signed-total support. Changed totalInt > 0 to totalInt /= 0. Historical negative spendings preserved; zero-total constraint maintained. Approved by Vasquez.

## Recent Work: Storage Rewrite Implementation (2026-05-14)


**Event:** Assigned to full-stack migration seam review for V24→V26 frontend safety.

**Task:** Validate frontend migration handling of stale transaction-addressed UI state; confirm no product changes needed.

**Finding:** The existing migration already chooses the safe behavior:
- Drops legacy edit/delete dialogs
- Neutralizes legacy edit/delete/detail messages and requests
- Clears migrated group transaction payloads
- Surfaces a reopen prompt instead of reinterpreting stale transaction details

**Decision:** Do not change product code. Legacy `TransactionId` values cannot be trusted to identify the same logical spending after the backend storage reshape.

**Outcome:** 
- ✅ Frontend migration safety confirmed
- ✅ Regression test charter captured for Vasquez follow-up
- ✅ Decision doc stored in team memory
- ✅ Repo validation passed

**Status:** Complete; coordinate with Vasquez on migration test expansion.

## 2026-04-28: Group Transaction Diff - Revision Implementation

**Event:** Revised scripts/compare_exports.py after Hudson's rejection by Vasquez.

**Task:** Reimplement per-group active-transaction comparison to replay the real `RequestGroupTransactions` seam instead of stopping at storage parity.

**Implementation:** 
- Legacy exports: Derive group rows from active legacy spendings in newest-first order
- Current exports: Derive group rows using backend's active-spending/active-transaction filter
- Compare ordered rendered rows (date, composed description, rendered share, rendered total)

**Validation:** Approved by Vasquez after code inspection and targeted Python seam assertions.

**Result:** Export diff tool now covers complete group-listing seam. Ready for merge/deployment.

**Key learning:** When implementing export/diff tools, must replay the exact backend/frontend paths that determine what users see, not just logical business invariants.

## 2026-05-14: Storage Rewrite Implementation — Transaction Storage Under Groups

### Session: Storage Rewrite Without Evergreen Migration

**Assignment: Rewrite transaction storage under groups while preserving the invariant and deferring Evergreen migration**

Completed the refactor-transactions model port implementation:

**Type Changes Landed:**
- BackendModel: Moved years to per-group StoredGroup, simplified nextId to single Int
- TransactionId: Added groupId field (encodes which group's timeline this transaction lives on)
- Person: Removed redundant id field, keys derive from Dict
- StoredGroup: New record replaces old Group, stores name inside record, scopes years and totalCredit
- Year/Month/Day: Simplified aggregation with flat totalCredit per level

**Codec & Backend Updates:**
- Updated `src/Codecs.elm` to serialize new record shapes with groupId in TransactionId
- Updated `src/Backend.elm` with new model initialization pattern
- Updated backend seams (e.g., userGroupsForPerson)
- **Critical:** Ensured all transactions from one spending share identical groupId (not per-transaction)

**Invariant Preservation:**
✅ Test: "all transactions from one spending share the same groupMembersKey" — PASS  
✅ Test: "participants in the same spending get the same due/owed view" — PASS  
✅ Manual: Group-credit aggregates match old nested structure  

**Validation Gates:**
- elm-format src/ tests/ --yes ✅
- lamdera make src/Frontend.elm --output=/dev/null ✅
- lamdera make src/Backend.elm --output=/dev/null ✅
- npm test (all passing) ✅
- ./check-codecs.sh ✅
- lamdera live → HTTP 200 ✅

**Scope Adherence:**

IN (completed):
- Type definitions and codec parity ✅
- Backend model initialization ✅
- Backend seams ✅
- Invariant-preserving logic ✅

OUT (deferred):
- Per-group year storage machinery (backend code that moves transactions)
- Evergreen migration files (V27 generation and logic)
- Global year iteration replacement (kept as placeholder)

### User Directive Context

Théo approved: "Proceed with the transaction storage model rewrite now, keep the due/owed and spending-wide groupMembersKey invariants intact, allow the backend model and transaction IDs to break, and defer the Evergreen migration until explicitly requested."

This approval unblocked the implementation without waiting for migration strategy.

### Decisions Recorded

- `.squad/decisions/decisions.md` — Merged decisions, including group-years runtime boundary and model port boundary
- `.squad/orchestration-log/2026-05-14T11:19:55Z-dallas.md` — Work summary and invariant validation
- `.squad/log/2026-05-14T11:19:55Z-storage-rewrite.md` — Session summary

### Next Phase

Ripley review of landed rewrite (invariant compliance check) → Then Evergreen migration planning.
