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

---

## 2026-05-14T11:20:56Z: User Directive — Storage Rewrite Approval

**By:** Théo Zimmermann (via Copilot)  
**Topic:** storage rewrite without Evergreen migration  
**Status:** APPROVED ✅

### Directive

Proceed with the transaction storage model rewrite now:
- Keep the due/owed and spending-wide groupMembersKey invariants intact
- Allow the backend model and transaction IDs to break (types will change)
- Defer the Evergreen migration until explicitly requested

### Rationale

User approval to unblock Dallas's implementation of the refactor-transactions model port without waiting for migration strategy.

---

## 2026-05-14: Model Port Boundary — Transaction ID + Storage Reshape

**Lead:** Ripley  
**Status:** APPROVED FOR IMPLEMENTATION ✅  
**User Approval:** Théo Zimmermann ("I'm OK with the backend model and transaction IDs changing...")

### Charter

Define the exact implementation scope Dallas should land NOW for the refactor-transactions model port, while explicitly deferring Evergreen migration work until user review.

**Critical invariant:** All transactions within a single spending MUST share identical group membership (now encoded in `TransactionId.groupId`). Violation causes silent data corruption in group-credit aggregates.

### Approved Type Changes

From refactor-transactions branch ARE APPROVED and should be landed as-is:

**BackendModel:**
```elm
type alias BackendModel =
    { spendings : Array Spending
    , groups : Dict GroupId StoredGroup
    , persons : Dict PersonId Person
    , nextId : Int
    , loggedInSessions : Set SessionId
    }
```
- Per-group year storage removes architectural mismatch
- Int-keyed persons/groups enable efficient membership queries
- Single nextId simplifies entity allocation

**TransactionId:**
```elm
type alias TransactionId =
    { groupId : GroupId       -- NEW: encodes which group's timeline this TX lives on
    , year : Int
    , month : Int
    , day : Int
    , index : Int
    }
```
- Moves groupMembersKey from redundant Transaction field into TransactionId
- Enables canonical per-group dated transaction storage
- groupId becomes the anchor for "which group members participated"

**Person & StoredGroup:**
- Person removes redundant `id`, keys derive from Dict
- StoredGroup replaces old Group, stores names inside records
- years and totalCredit now scoped to group (consistency)

### Implementation Scope IN

1. Type definitions as-is from refactor-transactions
2. Codec parity in `src/Codecs.elm` to match new record shapes
3. Backend model initialization in `init`
4. Backend seams already extracted and validated
5. No Evergreen migration files — leave `src/Evergreen/` untouched

### Implementation Scope OUT

1. **Invariant-breaking backend logic:**
   - ❌ DO NOT accept Backend changes that allow different transactions in same spending to have different groupIds
   - Current refactor-transactions Backend assigns groupId per transaction; must be fixed
   - ❌ DO NOT remove the "all transactions from one spending share the same groupMembersKey" test

2. **Storage reshape Backend logic:**
   - ❌ DO NOT land per-group year storage machinery (deferred)
   - ❌ DO NOT remove global year iteration (keep placeholder storage)

3. **Evergreen migrations:**
   - ❌ DO NOT generate `src/Evergreen/V27/` files yet
   - Migration logic depends on Backend changes and user review

### Invariant Preservation Rules

When a spending S contains transactions T1, T2, T3:
- T1.transactionId.groupId == T2.transactionId.groupId == T3.transactionId.groupId (same groupId)
- All transactions' member sets are derived from StoredGroup.members[groupId], not per-transaction

**Validation checklist:**
1. Test: "all transactions from one spending share the same groupMembersKey" — MUST PASS
2. Test: "participants in the same spending get the same due/owed view" — MUST PASS
3. Manual: Verify group-credit aggregates match old nested structure
4. All gates: elm-format, lamdera make (both), npm test, ./check-codecs.sh, lamdera live HTTP 200

### Deferred to Next Phase

- Per-group year storage Backend machinery (needs Evergreen V27)
- Aggregation flattening validation (needs report equivalence proof)
- All Evergreen migration logic (user approval required first)

---

## 2026-05-14: Group-Owned Year Storage — Spending-Wide Report Metadata Preserved

**Owner:** Dallas  
**Artifact:** refactor-transactions branch (group-owned transaction storage)  
**Status:** APPROVED FOR TYPES ✅

### Context

The storage move places dated transactions under `BackendModel.groups` and changes `TransactionId` to include `groupId`. Prior review flagged two invariants that must not regress: due/owed consistency and a single spending-wide `groupMembersKey` across every transaction emitted by one spending.

### Decision

- Keep the refactor's group-owned year/month/day transaction storage and group-scoped `TransactionId`
- Preserve the existing global `totalGroupCredits : Dict String (Dict String (Amount Credit))` cache
- Preserve per-transaction `groupMembersKey` and `groupMembers`, computed once per spending and copied onto every emitted transaction row
- Keep `Person.belongsTo` keyed by spending-wide member-set strings, not by `GroupId`

### Why

The group-owned storage solves the model rewrite, but report correctness depends on aggregating by the full participant set of a spending rather than by each line's storage group. Without the preserved spending metadata, mixed-creditor spendings drift and user/group due-vs-owed views disagree.

### Implementation Status

✅ Types defined and approved  
✅ Codecs updated  
✅ Backend initialization completed  
✅ Invariant tests pass (groupMembersKey uniformity, due-vs-owed consistency)  
⏳ Per-group year storage machinery (deferred)  
⏳ Evergreen migration (deferred until user reviews)

### Follow-up Boundary

Evergreen migration is intentionally deferred. Any migration pass must rebuild the new group-owned storage and extend migrated `TransactionId` values with `groupId` while proving stored `Spending.transactionIds` still resolve to the intended rows.
# Evergreen V28→V31 Migration Strategy

**Lead:** Ripley  
**Status:** PREPARED (awaiting implementation)  
**Date:** 2026-05-14

## Migration Context

**V28 → V31 Delta:**
- **Storage ownership:** `BackendModel.years : Dict Int Year` → Per-group `StoredGroup.years : Dict Int Year`
- **Group keys:** `groups : Dict String Group` → `groups : Dict GroupId StoredGroup` (string → int keys)
- **Person keys:** `persons : Dict String Person` → `persons : Dict PersonId Person` (string → int keys)
- **TransactionId:** No `groupId` field → Added `groupId` field at front (canonical new field)
- **Person record:** `Person { id : Int }` → `Person { name : String }` (id becomes key; name is persisted)
- **Model:** Added `nextId : Int`; removed `years` and `nextPersonId : Int` (consolidation)

## Clean Migration Obligations

### 1. **Root Storage Rebuild (BackendModel)**

Old structure (V28):
```elm
{ years : Dict Int Year               -- global, per-year indexed storage
, spendings : Array Spending
, groups : Dict String Group          -- group name → {personName → Share}
, persons : Dict String Person        -- person name → {id : Int, belongsTo}
, nextPersonId : Int
, ...
}
```

New structure (V31):
```elm
{ spendings : Array Spending           -- unchanged
, groups : Dict GroupId StoredGroup    -- group id → {name, members, years, totalCredit}
, persons : Dict PersonId Person       -- person id → {name, belongsTo}
, nextId : Int                         -- unified entity counter
, totalGroupCredits : Dict ...         -- preserved
, loggedInSessions : Set SessionId     -- preserved
}
```

**Correct migration:**
1. Assign unique `GroupId` to each group name (allocate from `nextId`)
2. Assign unique `PersonId` to each person name (allocate from `nextId`)
3. Rebuild `StoredGroup.years` by **copying** old `BackendModel.years` content into the corresponding group's years dict
4. Rebuild `StoredGroup.members` by mapping old string group membership to new `PersonId` keyed membership
5. Set `nextId` to max(groupIds) + 1 (or max(personIds) + 1)

### 2. **TransactionId.groupId Field**

Old structure: `{ year, month, day, index }`  
New structure: `{ groupId, year, month, day, index }`

**Correct migration:**
- For each Transaction in storage, determine which group it belongs to by:
  - Find the Spending (via `transaction.spendingId`)
  - Find the group membership from that spending (via `spending.groupMembersKey` lookup)
  - Map group name → `GroupId` from the reconstructed groups dict
- Insert `groupId` at the front of TransactionId

**Critical invariant:** All transactions within a single spending must have the same groupId. Verify this post-migration.

### 3. **Person Record Mapping**

Old: `Dict String Person { id : Int, belongsTo : Set String }`  
New: `Dict PersonId Person { name : String, belongsTo : Set String }`

**Correct migration:**
- For each `(personName, {id, belongsTo})` in old persons:
  - Create `newId = personId++`  (or better, reuse old.id if stable)
  - Store `(newId, { name = personName, belongsTo })`
  - Rebuild Set String → Set PersonId for `belongsTo` ??? **NO**: `belongsTo` remains `Set String` (group names, not ids)
    Actually, check current Types... **update strategy** below

### 4. **Frontend State Reset (Safe Seams)**

Old `FrontendModel.groupTransactions : List { transactionId: TransactionId, ... }`

Since `TransactionId` changed structure (added `groupId`), old in-flight references are invalid. **Safe reset:** Clear `groupTransactions` to empty list (user will refresh).

---

## Verification Checklist

After implementing migration:
- ✅ All group names get stable GroupIds
- ✅ All person names get stable PersonIds
- ✅ Every Transaction gets correct groupId (all in same spending have same groupId)
- ✅ `nextId` is set such that new allocations don't collide
- ✅ `BackendModel.years` becomes `StoredGroup.years` without data loss
- ✅ Frontend `groupTransactions` is cleared (safe reset)
- ✅ Tests: Run `npm test` and `lamdera live` HTTP 200

## Rejection Criteria (Avoidable Churn)

❌ **Do NOT:**
- Set groups or persons to empty Dict if old data exists
- Discard `BackendModel.years` or `persons` without reconstruction
- Assign arbitrary `groupId` / `PersonId` without stable mapping
- Leave any `Unimplemented` in final migration file
- Mix generated V31/Types.elm edits with migration logic (keep them separate)

---

## Implementation Sequence

**ASSIGNED TO:** Dallas (migration specialist)

1. **Keep V31/Types.elm as-is** (autogenerated, clean)
2. **Implement V31 migration file** (`src/Evergreen/Migrate/V31.elm`) with:

   **A. Group and Person ID Allocation**
   ```elm
   -- Pass 1: Allocate stable IDs from old data
   groupNameToId : Dict String GroupId  -- map old names to new GroupIds
   personNameToId : Dict String PersonId -- map old names to new PersonIds
   nextIdAfterAllocations : Int         -- start new allocations here
   
   -- Strategy: 
   -- - Use old.nextPersonId as a base for PersonId counter
   -- - Assign GroupIds starting from max(oldPersonIds) + 1
   -- - Set final nextId to highest allocated ID + 1
   ```

   **B. BackendModel.groups Rebuild**
   ```elm
   -- For each (groupName, Group) in old.groups:
   --   Look up groupId = groupNameToId[groupName]
   --   Rebuild StoredGroup:
   --     { name = groupName
   --     , members = rebuild from Dict String Share using personNameToId
   --     , years = lookup old.years and assign to this group
   --     , totalCredit = init to Amount 0 (recomputed on first backend run)
   --     }
   ```

   **C. BackendModel.persons Rebuild**
   ```elm
   -- For each (personName, Person) in old.persons:
   --   Look up personId = personNameToId[personName]
   --   Create new Person:
   --     { name = personName
   --     , belongsTo = old.belongsTo (unchanged)
   --     }
   --   Store as (personId, newPerson) in new dict
   ```

   **D. TransactionId.groupId Assignment**
   ```elm
   -- For each Spending in old.spendings:
   --   Determine spending.groupMembersKey
   --   Use new groups dict to find which GroupId holds those members
   --   For each Transaction referenced by spending.transactionIds:
   --     Insert that groupId into the TransactionId
   --     VERIFY: All transactions from same spending get same groupId (invariant check)
   ```

   **E. Frontend Safe Reset**
   ```elm
   -- groupTransactions = [] (cleared, user must refresh)
   -- All other frontend state migrated as-is (dialog models, page, etc.)
   ```

3. **Validation gates (must ALL pass):**
   - `elm-format src/ tests/ --yes` (clean formatting)
   - `lamdera make src/Frontend.elm --output=/dev/null` (Frontend compiles)
   - `lamdera make src/Backend.elm --output=/dev/null` (Backend compiles)
   - `npm test` (all tests pass)
   - `lamdera live` and verify HTTP 200 (server functional)
   - Manual test: Load the app, verify it doesn't crash
   
4. **Commit separately:** "Implement Evergreen V31 migration logic"
   - Must include only `src/Evergreen/Migrate/V31.elm` changes
   - No other files in this commit
   
5. **Optional final check:** `lamdera check --force` (Lamdera coherence verification)

---

## Diff Quality

A **clean migration diff** will show:
- ✅ V31/Types.elm: Autogenerated (large change, expected)
- ✅ Migrate/V31.elm: All `Unimplemented` replaced with logic
- ✅ No other Evergreen files touched
- ✅ No product code changes in this commit
- ❌ Zero `Unimplemented` remaining in the final file
