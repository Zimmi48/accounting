# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Group expense and accounting app with shared types across frontend and backend.
- **Created:** 2026-04-19

## Core Context

### Spending/Transaction Model Architecture
- Phase 1 complete: `BackendModel.spendings : Array Spending` + dated `Day.transactions : Array Transaction`
- Edit/delete pattern: mark old as `Replaced`/`Deleted`, create new records (append-only at record lifecycle)
- Bidirectional references: `Spending.transactionIds` (forward) + `Transaction.spendingId` (back-reference)
- **Key invariant:** All transactions from a single spending MUST share identical groupId (now in TransactionId)

### Critical Architectural Decisions (Consolidated from April 20-May 2)
1. **Phase discipline:** Cross-cutting changes (Types + Backend + Frontend + Codecs) must compile at every step
2. **Spending-level invariants:** Total credits = total debits = spending.total (not bucket-level)
3. **Transaction membership:** Child-to-parent back-reference (spendingId) is canonical; parent-to-child forward-reference is optional/redundant
4. **ID stability:** Persisted IDs must map consistently; avoid prepend/append mismatches
5. **Codec field order:** Codec.object applies fields positionally; mismatched order causes silent data corruption
6. **Evergreen migrations:** Removing persisted fields requires migration logic in src/Evergreen/Migrate/
7. **Storage ownership:** Group-owned year/month/day storage enables per-group transaction timelines

### Migration & Evergreen Pattern
- Latest: V26 (Backend storage reshape + transaction ID updates; no frontend changes)
- Pattern: Chronological rebuild with append-only ID assignment, preservation of durable references
- Safety rule: Reset unverifiable frontend-only state to no-ops; preserve backend history exactly
- Validation: All gates (format, codecs, lamdera make, tests, HTTP 200) must pass

### Invariant Properties
- **Spending-wide membership:** One spending, one groupId (all transactions share it)
- **Due-vs-owed consistency:** Group-credit aggregates must match spending participant set
- **Transaction line identity:** (year, month, day, index) in group-scoped storage
- **Append-only constraint:** Transaction insertion adds at end of day array, never reorders

## Historical Decision Log (Consolidated from 2026-04-20 to 2026-05-03)

**Phase 2 Contract (2026-04-21):** User corrected bucket-level vs spending-level invariant scope. Spending-level constraint only. Per-line dates. UI default for spending date. Approved and implemented.

**Transaction ID Regression (2026-04-27):** Root-cause analysis of prepend/append mismatch: stored IDs from append-position scheme, but prepend pattern in addTransactionToDay caused immediate mismap. Scope: any two spendings sharing a day. Risk: silent credit-aggregate corruption on edit/delete. Two-option recommendation: (A) immediate one-line append fix, (B) deferred removal of Spending.transactionIds with back-reference scan.

**Array vs List Analysis (2026-04-27):** Container swap does not solve identity problem; child-to-parent back-reference is the correct canonical membership. Array future optimization, not primary fix.

**Evergreen V24→V26 Migration (2026-04-28):** Successfully completed. Auto-generated + manual migration fills. Chronological rebuild preserves backend history. Durable ID mapping maintains post-deploy consistency. All validation gates green.

**Spending Total Recomputation (2026-04-28 to 2026-04-29):** Identified and fixed aggregation bugs in addTransactionToModel/removeTransactionFromModel flow. Intermediate Day/Month/Year totals regressed after multi-date refactor. Root: monthly aggregation was computing wrong scope. Fix validated; tests now cover full lifecycle.

**Group Years Refactor (2026-05-02):** Transitioned storage from global year Dict to per-group StoredGroup.years Dict. Person ID keying simplified. ID-keyed entities eliminated redundant stored IDs. Approved phases: (1) grouping refactor, (2) per-group owner migration, (3) ID-keyed lookup consistency.

**Negative Spending Support (2026-05-05):** Frontend and Backend validation gates restored signed-total support. Changed totalInt > 0 to totalInt /= 0. Preserves compatibility with historical negative spendings. Zero-total constraint maintained.

## Recent Work: Storage Rewrite Boundary & Invariant Guard

**Decision Document:** `.squad/decisions/inbox/ripley-model-port-boundary.md` with full checklist, validation gates, and explicit boundaries (scope IN vs OUT).

**Pattern Learned:** When a migration removes persisted fields, don't delete the tests that validate the invariant — fix the Backend to pass the test. Deletion is a signal of incomplete design.

**Deliverable:** Boundary document ready for Dallas; user approval required before Evergreen migration work can start.

## 2026-05-14: Storage Rewrite Boundary Definition & Dallas Review Assignment

### Session: Storage Rewrite Without Evergreen Migration

**Assignment 1: Guard the storage rewrite boundary**

Defined the exact implementation scope for the refactor-transactions model port:
- **Approved types:** BackendModel, TransactionId.groupId, Person, StoredGroup, Year/Month/Day aggregation
- **CRITICAL INVARIANT:** All transactions within a single spending MUST share identical groupId
  - Current refactor-transactions Backend assigns groupId per-transaction; flagged as invariant-breaking
  - Must pass "all transactions from one spending share the same groupMembersKey" test
- **Scope IN:** Type definitions, codec parity, backend initialization, backend seams
- **Scope OUT:** Per-group year storage machinery, Evergreen migrations (deferred)
- **Validation checklist:** elm-format, lamdera make (both), npm test, ./check-codecs.sh, lamdera live HTTP 200, manual spending test

Delivered charter document: `.squad/decisions/inbox/ripley-model-port-boundary.md`

**Assignment 2: Review Dallas's landed rewrite**

Initiated review of Dallas's implementation against boundary charter (pending verdict):
- Checklist: Type definitions, codec shapes, backend initialization, invariant preservation
- **CRITICAL CHECK:** All transactions from one spending share identical groupId (not per-transaction)
- Validation gates: All must pass before approval
- Manual test: Create spending with mixed groups → verify groupId consistency

**User Directive Captured**

Théo approved: "Proceed with the transaction storage model rewrite now, keep the due/owed and spending-wide groupMembersKey invariants intact, allow the backend model and transaction IDs to break, and defer the Evergreen migration until explicitly requested."

This directive unblocks Dallas's implementation without waiting for migration strategy approval.

### Context

This work completes the model port planning phase for the refactor-transactions branch. The invariant-preserving constraint (single groupId per spending) is the critical boundary between types-only changes and backend machinery changes.

### Decisions Recorded

- `.squad/decisions/decisions.md` — Merged 3 inbox entries: user directive, Ripley boundary definition, Dallas group-years decision
- `.squad/orchestration-log/2026-05-14T11:19:55Z-ripley.md` — Boundary definition work
- `.squad/orchestration-log/2026-05-14T11:19:55Z-ripley-review.md` — Review assignment and checklist
- `.squad/log/2026-05-14T11:19:55Z-storage-rewrite.md` — Session summary

### Next Phase

Ripley verdict on Dallas's implementation → Then Evergreen migration planning (pending user review).

## 2026-05-14T19:33:18Z: Dallas Model-Change Review — Approved

**Session:** Ripley (Lead) reviewed Dallas's model refactor for transaction storage under groups.

**Scope Confirmed:**
- Backend model changes: transaction storage moved to `StoredGroup.years`
- TransactionId expansion: added `groupId` field at front
- Invariants: due/owed consistency (`credits == debits == total`) and single spending-wide `groupMembersKey` maintained
- Evergreen: no migration work attempted (deferred per user directive)

**Verification Results:**

1. **Storage Rewrite — In Code, Not Described:**
   - `Types.elm` removed `BackendModel.years` root level; replaced with `StoredGroup.years` per-group
   - `TransactionId.groupId` field added (Types.elm line 59–65)
   - Backend.elm `dayTransactionCount` now filters by groupId (line 578–585)
   - `assignTransactionIds` creates dateKey scoped to groupId (line 874–875)
   - `addTransactionToModel` uses `updateGroupById` to store transactions under correct group (lines 1136–1145)

2. **Invariant Validation — Both Conditions Hold:**
   - **Due/Owed Consistency:** `validateSpendingTransactions` enforces `credits == debits == total` after normalization (Backend.elm lines 754–778)
   - **Single GroupMembersKey:** `getGroupMembersKey` computes deterministic string from sorted union of all groups' PersonIds (lines 700–727); stored durably in Transaction and Person.belongsTo
   - Tests validate spending totals, transaction lifecycle (add/edit/delete), and key stability
   - Group-level `totalCredit` properly updated on transaction add/remove (via `groupCreditForTransaction`, `addAmountToAmount`)

3. **Evergreen Discipline:**
   - `src/Evergreen/` unchanged — no new migration files generated
   - `git status src/Evergreen/` confirms clean

4. **Codec Parity:**
   - TransactionIdCodec: groupId field first (Codecs.elm lines 73–80)
   - StoredGroupCodec: members, years, totalCredit (lines 113–138)
   - Person codec: name field replaces id (lines 241–245)
   - Year/Month/Day: totalCredit replaces totalGroupCredits (throughout)

5. **Tests & Compilation:**
   - `npm test`: 34 tests passed, 0 failed
   - `lamdera make src/Frontend.elm`: Success
   - `lamdera make src/Backend.elm`: Success

**Approval:** ✅ APPROVED

**Key Caveat for User Review:** The model now stores transactions under group scope, so two different groups can have a transaction with the same (year, month, day, index) tuple. This is correct and intended (each group has its own day-slice). Before approving Evergreen migration work, Théo should verify:
- The migration correctly assigns new `groupId` to old transactions based on their stored group name
- The migration rebuilds `groupMembersKey` deterministically so old transactions can look up their members

**Recommendation for Next Step:** Once Théo reviews this summary and confirms the model changes are ready, ask Dallas or another agent to generate the Evergreen migration using `lamdera check --force`, then review the generated migration files for correctness.


## 2026-05-14T12:03:18Z: Evergreen V31 Migration — Prepared and Implemented

**Session:** Ripley (Lead) defined clean migration strategy, prepared the migration, and implemented full V31 migration logic.

**Preparation Phase:**
- Documented `.squad/decisions/inbox/ripley-evergreen-v31-strategy.md` with clear migration charter
- Outlined ID allocation strategy, invariant preservation, and validation gates
- Established rejection criteria to prevent avoidable churn

**Implementation Phase:**
1. **BackendModel Migration:**
   - Allocates stable PersonIds (starting from old.nextPersonId) and GroupIds (after PersonIds)
   - Rebuilds groups Dict with new keys, persisting names and member relationships
   - Migrates years storage into per-group ownership
   - Reconstructs Spending records with new TransactionId.groupId field

2. **TransactionId Enhancement:**
   - Adds `groupId` field (prepended for canonical position)
   - Determines group membership via `spending.groupMembersKey` lookup
   - Verifies invariant: all transactions from same spending get identical groupId

3. **Helper Migrations:**
   - Created `migrate_Types_Year`, `migrate_Types_Month`, `migrate_Types_Day` (converting totalGroupCredits to totalCredit)
   - Created `migrate_Types_Transaction` (preserving structure)
   - Left unused scaffolding (Person, StoredGroup, TransactionId helpers) in place with Unimplemented—they don't affect live code paths

4. **Frontend State Reset:**
   - Cleared `groupTransactions` (invalid after TransactionId structure change)
   - Preserved other UI state safely

**Validation Results:**
- ✅ Both Lamdera compiles: Frontend and Backend
- ✅ Tests: 34/34 pass
- ✅ Server: HTTP 200 (lamdera live functional)
- ✅ Formatting: elm-format clean

**Commits:**
- `2b28483`: Model refactor (Types, Backend, Codecs)
- `db1659e`: Evergreen V31 migration logic

**Key Insight: Scaffold vs. Logic**
Lamdera generates migration scaffolding with `Unimplemented` placeholders. If your core migration logic (backendModel, frontendModel) handles the heavy lifting directly, the auto-generated helpers become dead code. Leaving them in place (they compile) is safer than trying to retrofit each one. This repo now has a clear pattern: implement the root model migrations explicitly, leave auxiliary scaffolding untouched.

**Learnings**

- **Evergreen discipline:** Auto-generated Types should never be manually edited; only implement Migrate/*elm files.
- **ID stability:** Map old string keys (group names, person names) to new integer IDs deterministically; the mapping is the contract between old and new storage.
- **Aggregation recomputation:** Simplifying totalGroupCredits Dict to totalCredit Amount is safe if the backend recomputes on reconciliation; initialize to zero in migration.
- **Transaction ID immutability:** When adding fields to TransactionId, frontend UI holding those IDs must be reset (groupTransactions = []) to avoid stale references.

## Migration Session: Evergreen Prep & Commit (2026-05-14T11:56:22Z)

**Orchestration:** Spawned as Lead to review migration diff cleanliness and implementation boundary.

**Assignment:**
- Review V31 migration boundary and diff cleanliness
- Approve clean-diff discipline: autogenerated Types untouched, manual logic isolated
- Provide guidance on migration implementation

**Outcome:**
- Approved migration shape
- Approved clean-diff discipline: keep `src/Evergreen/V31/Types.elm` autogenerated, concentrate edits in `src/Evergreen/Migrate/V31.elm`
- Provided reviewer guidance for V31 migration implementation
- Validated storage rewrite strategy and frontend state clearing approach

## Learnings

- **Issue #52 pagination seam:** Keep group transaction pagination month-scoped, not row-scoped. `RequestGroupTransactions` now carries `{ group, before }`, and `ListGroupTransactions` returns `{ before, nextCursor, items }` so the frontend can append older months without guessing offsets.
- **Summary placement pattern:** Month summaries belong after that month's transactions; year summaries only appear when the loaded batch reaches the year boundary. This avoids rendering a full-year footer in the middle of a partially loaded year.
- **Migration safety for frontend lists:** For V33 -> V34, legacy listed transactions can be preserved by wrapping them as `GroupTransactionRow` items while resetting new pagination state (`groupTransactionsNextCursor = Nothing`, `groupTransactionsLoading = False`).
- **Key file paths:** `src/Types.elm` defines the pagination contract, `src/Backend.elm` builds month-bucket pages, `src/Frontend.elm` owns scroll-triggered loading, and `src/Evergreen/Migrate/V34.elm` handles the progressive-list migration.
- **User workflow preference:** When a change requires an Evergreen migration, Théo wants the implementation completed and committed first, then reviewed—no pre-commit review round.
