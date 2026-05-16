# Decisions Log
## Hicks: Spending Submit Gating Must Share Backend Signed Balance Invariant

**Date:** 2026-05-15  
**Owner:** Hicks  
**Issue:** #47  
**Status:** APPROVED ✅

### Context

Issue #47 requested restoration of frontend spending dialog submit button gating while preserving the newer backend validation. The dialog submit button must stay disabled until credits, debits, and total all agree.

### Decision

Use the same signed spending invariant on the frontend that the backend already enforces: submission is allowed only when `sum credits == sum debits == total` and `total /= 0`.

### Rationale

This keeps negative-total spendings working, matches the approved #50 backend semantics, and avoids a seam where the button looks enabled but the `Submit` branch still accepts an invalid payload.

### Files Modified

- `src/Frontend.elm` — submit button gating logic
- `tests/FrontendTests.elm` — submit gate regression tests

---
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

# Month fold state without migration

- **Context:** The rejected month-folding revision used native `<details>` state, which reopened collapsed months on rerender. The replacement had to remember folds across pagination and refresh without opening Evergreen migration work.
- **Decision:** Keep month fold state frontend-local by encoding it in `groupTransactions` with a duplicated `GroupTransactionMonthSummary` marker for folded months, keyed by `(year, month)`.
- **Why:** This preserves fold state across normal list normalization, load-more merges, and mutation-triggered refresh replays without changing `FrontendModel` shape or introducing migration work.
- **Implementation notes:** `toggleGroupTransactionMonthFold` flips the marker, `groupTransactionViewSections` interprets it, and `groupTransactionsFromBackend` reapplies remembered folded months after normalizing backend items.

# Hicks decision: persist theme through the URL

- Date: 2026-05-16
- Context: Issue #53 needs light/dark mode to survive a browser reload, but adding frontend/shared model fields would create unnecessary Lamdera migration work for a browser-local preference.
- Decision: Keep theme persistence frontend-local by encoding dark mode in the page URL (`?theme=dark`), hydrating `theme` from `init`/`UrlChanged`, and updating the current route with `Nav.replaceUrl` when the toggle changes.
- Why:
  - Reload persistence comes from the browser URL, so there is no JS/local-storage plumbing and no Evergreen churn.
  - Existing routing behavior stays path-based; the query only carries the UI preference and is preserved across internal navigation.
  - The seam is easy to test with pure helpers for URL parsing and query rewriting in `tests/FrontendTests.elm`.

# Hicks decision: month fold toggle uses native details

- Date: 2026-05-16
- Context: Transaction list month headers already exist in the paginated list and the requested fold state is presentation-only.
- Decision: Render each month bucket in `src/Frontend.elm` as a native `<details open>` section with the existing month summary row as the `<summary>` toggle, while leaving year summaries as standalone headers.
- Why:
  - Keeps months expanded by default without storing extra frontend model state.
  - Avoids changing shared Lamdera types, so this UI polish does not trigger Evergreen migration work.
  - Preserves current backend pagination, reverse chronology, load-more, and refresh-depth behavior because the underlying `groupTransactions` list shape stays unchanged.

# Ripley — Issue #53 revision
## Context
Hicks's first fix correctly made theme choice survive reloads by putting it in the URL, but the toggle rebuilt URLs from `Page -> path` only. That silently dropped page-local state on `Import String`, `Json (Maybe String)`, and `NotFound` once the browser processed the follow-up `UrlChanged`.
## Decision
Keep theme persistence URL-backed and migration-free, but widen the URL contract just enough for the stateful frontend pages touched by the toggle seam:
- keep `theme` in the query string
- encode `Import` drafts and `Json` exports in the fragment when `pageUrl` rebuilds the current page URL
- encode `NotFound` as an explicit fragment sentinel so toggling theme does not collapse the page back to `Home`
- hydrate those values in `routing`
## Why this shape
It fixes reload persistence without adding shared model fields, without touching Evergreen, and without depending on browser ports or JS storage. The contract change stays frontend-local and only applies where the toggle-generated URL would otherwise erase live state.
## Review gate
Tests must exercise the real seam by round-tripping `pageUrl -> Url -> routing` for `Import`, `Json`, and `NotFound`, not only helper-level query parsing.

# Vasquez review — folded month load-more stall

- Commit reviewed: `9fb2827` (`Fix folded month load-more stall`)
- Verdict: REJECT
- Specific seam: the fold-triggered load-more path is still under-proved. The new test only shows that `groupTransactionsScrollStateFromViewport` plus `shouldLoadMoreGroupTransactions` would return `True` for a synthetic viewport; it does not prove the real `ToggleGroupTransactionMonthFold -> checkGroupTransactionsViewport -> GroupTransactionsViewportChecked -> requestMoreGroupTransactions` flow that the user reported.
- Code assessment: the implementation in `src/Frontend.elm` is plausible — the fold toggle now schedules `checkGroupTransactionsViewport`, and the viewport callback reuses the existing load-more threshold logic — but the branch is effectful and the review artifacts do not pin it end to end.
- Why this is not approvable:
  - `tests/FrontendTests.elm` does not exercise the fold message/update seam or show that the viewport check command is actually scheduled after folding.
  - The added test models an already-at-bottom list with `scrollTop = 0` and `scrollHeight = clientHeight`, not the reported user seam where a large expanded month shrinks and newly reveals the list end.
  - No regression proof shows that folding a blocking month results in an actual `RequestGroupTransactions` for older history.
- Validation run: `elm-format --validate src/ tests/`, `npm test`, `lamdera make src/Frontend.elm --output=/dev/null`, `lamdera make src/Backend.elm --output=/dev/null`, and HTTP 200 from `lamdera live --port=8002` via `curl` all succeeded in repo validation.
- Required next revision owner: Hicks (or any non-Dallas implementer).
- Required for approval: add proof-grade coverage for the real fold-to-load-more update path, or extract a pure follow-up helper that the toggle branch consumes so the request for older pages becomes directly testable.

# Folded month viewport seam review

- Reviewer: Vasquez
- Commit: `1d80415` (`Fix folded month viewport seam`)
- Verdict: **APPROVED**
## Why this clears the seam

The implementation now routes the user path through testable helpers without changing the behavior shape:

1. `ToggleGroupTransactionMonthFold` delegates to `toggleGroupTransactionMonthFoldPlan` and still re-checks the viewport whenever older history can load.
2. `GroupTransactionsViewportChecked` delegates to `groupTransactionsViewportLoadMorePlan`, which reuses the existing bottom-of-list guard and emits the older-page request.
3. `tests/FrontendTests.elm` now pins the exact reported seam: before folding there is no request, after folding the viewport is rechecked, loading flips on, and the frontend requests `RequestGroupTransactions { group = "Trip", before = Just { year = 2025, month = 4 }, pages = 1 }`.
## Validation

- `npm test` ✅ (71 tests)
- `lamdera make src/Frontend.elm --output=/dev/null` ✅
- `lamdera make src/Backend.elm --output=/dev/null` ✅
## Review note

This proof is acceptable because the production `update` branches are now thin wrappers around the extracted plan helpers. If those branches later grow independent logic, the seam must be reproved at the message/update level again.

# Issue #53 and #51 final review

- Reviewer: Vasquez
- Reviewed author: Ripley
- Timestamp: 2026-05-16T18:43:00Z
- Verdict: **APPROVED**
## Why this clears #53

1. Theme bootstrap now survives reloads because `src/Frontend.elm` hydrates the theme from the URL in `init` and refreshes it again on `UrlChanged`.
2. The earlier state-loss regression is closed: `ToggleTheme` rewrites through `pageUrl`, and `pageUrl`/`routing` now preserve `Import` drafts, exported `Json` payloads, and `NotFound` via fragments instead of collapsing those pages back to bare paths.
3. The new frontend tests hit the real seam tightly enough for this implementation shape: they prove theme query hydration, URL rewriting, and stateful-page round trips for `Import`, `Json`, and `NotFound`, which is exactly where the previous patch failed.
## Why this clears #51

1. Dark mode no longer uses the muddy low-contrast green; the accent is raised to the same bright green already used in light mode.
2. Action text on that accent is now black, which is the sensible contrast partner for the brighter fill and avoids the washed-out light-on-green pairing.
3. `tests/FrontendTests.elm` now locks that palette contract so a future dark-mode tweak cannot silently drift back to a dimmer/softer combination.
## Validation

- `elm-format --validate src/ tests/` ✅
- `lamdera make src/Frontend.elm --output=/dev/null` ✅
- `lamdera make src/Backend.elm --output=/dev/null` ✅
- `npm test` ✅ (80 tests)
- `lamdera live` HTTP 200 ✅
## Review note

No shared-type, migration, `elm.json`, or `package.json` churn was introduced for this fix set. This stays frontend-local, which is the right scope for both issues.

# Issue #53 review — REJECT

- Reviewer: Vasquez
- Reviewed author: Hicks
- Timestamp: 2026-05-16T18:32:20Z
- Verdict: REJECT
- Reassign next revision to: Ripley
## Why

1. Reload persistence itself is now wired through `init`/`UrlChanged` with `?theme=dark`, so the intended bootstrap seam is finally present.
2. The patch introduces a new navigation regression at `src/Frontend.elm:ToggleTheme`: `Nav.replaceUrl model.key (pageUrl theme model.page)` rebuilds URLs from `pagePath` only, but `Page` carries extra state on `Json (Maybe String)`, `Import String`, and `NotFound`. The resulting `UrlChanged` resets `/json` to `Json Nothing`, clears `/import` drafts back to `Import ""`, and turns `NotFound` into `/`.
3. `tests/FrontendTests.elm` only proves helper parsing/rewriting (`themeFromUrl`, `themeFromUrlOr`, `urlStringWithTheme`). It never exercises the real `ToggleTheme -> Nav.replaceUrl -> UrlChanged` seam on those stateful pages, so the regression is currently unguarded.
## Validation observed

- `npm test` passes (76/76)
- `lamdera make src/Frontend.elm --output=/dev/null` passes
- `lamdera make src/Backend.elm --output=/dev/null` passes

Passing validation is not enough here because the missing coverage is exactly how the state-loss bug escaped.
## Month Folding Review Rejection (Vasquez, 2026-05-16)

**Status:** Rejected at commit `e8e6063`.

**Verdict:** The requested month-folding change is not reviewable as implemented because no fold/unfold behavior is present in the submitted artifacts.

**Why rejected:**
- `src/Frontend.elm` still renders `model.groupTransactions` straight through `viewGroupTransactionListItem`; month summaries are visible, but there is no month-specific folded state, no toggle message, and no conditional hiding of that month's rows.
- `src/Types.elm` contains pagination and summary list-item types only; there is no shared contract for month folding that would explain the missing behavior.
- `tests/FrontendTests.elm` proves pagination merge order, chronology normalization, load-more depth bookkeeping, and refresh helpers, but it does not prove the month-fold seam the task asked for:
  - selected month header remains visible
  - only the selected month's rows hide/show
  - other months remain in chronological order
  - load-more still appends older months correctly
  - refresh depth logic stays stable while folded state is applied

**Migration note:** No hidden migration work was found in the reviewed artifacts.

**Required for approval:** Land an actual fold-state implementation and add explicit regression tests for the UI seam above before resubmitting.

# Vasquez review — month fold state approve 522dbe9

- Commit reviewed: `522dbe9` (`Persist month fold state`)
- Verdict: APPROVE
- Reason: fold state is now Elm-managed in `src/Frontend.elm` via `ToggleGroupTransactionMonthFold`, stored in frontend-local transaction-list state, and does not introduce a shared-type migration seam.
- Proof reviewed:
  - `tests/FrontendTests.elm` proves only the targeted month folds, year headers remain outside foldable sections, and reverse chronology is restored on fresh reload.
  - `tests/FrontendTests.elm` proves load-more preserves the chosen folded month when older history arrives.
  - `tests/FrontendTests.elm` proves `operationSuccessfulRefreshPlan` replays the remembered page depth without clearing folded items, which is the refresh-depth replay seam for mutation-triggered reloads.
- Guardrail: future refactors must keep fold identity keyed by `(year, month)`, not list position.

# Vasquez — Month fold state review

- Verdict: Reject the current artifact.
- Exact remaining seam: `src/Frontend.elm` still renders month sections with native `<details open>` and no Elm-managed fold state or toggle message, so a collapsed month reopens on rerender (load-more, refresh-depth replay, transaction check, theme change, viewport change).
- Why this is not proved safe: `tests/FrontendTests.elm` only covers `groupTransactionViewSections` and `groupTransactionMonthSectionItems`, which validate helper grouping/hiding but never drive the real update/render seam that must preserve fold choice across rerenders.
- Reviewer consequence: Dallas is locked out for the next revision cycle unless a different agent lands a stateful fix with composed regression coverage.

# Review: Month Folding Rerender Seam (2026-05-16T10:31:52Z)

**Reviewer:** Vasquez

**Artifact:** commit `eb161df` (`Add month folding in transaction list`)

**Verdict:** Rejected

**What holds:**
- Month summaries are now rendered as native fold toggles and start expanded by default.
- Year headers stay outside the foldable month buckets because `groupTransactionViewSections` keeps them as standalone items.

**Exact remaining seam:**
- `src/Frontend.elm` renders each month with `<details open>` in `viewFoldableGroupTransactionMonthSection`, but there is no fold state in `FrontendModel`, no message for toggling a month, and no keyed persistence by `(year, month)`.
- A user can close a month in the browser, but any Elm rerender that touches the list reapplies the hard-coded `open` attribute and re-expands it. That includes load-more merges, `OperationSuccessful` refreshes, transaction check toggles, theme changes, and viewport updates.
- `tests/FrontendTests.elm` only proves the grouping helper (`groupTransactionViewSections`) and the visibility helper (`groupTransactionMonthSectionItems`). It does **not** prove the actual fold/unfold seam at the rendered update path, nor that load-more / refresh leave the chosen month folded while chronology, year headers, and remembered page depth stay intact.

**Validation run:**
- `npm test` ✅
- `lamdera make src/Frontend.elm --output=/dev/null` ✅
- `lamdera make src/Backend.elm --output=/dev/null` ✅
- `curl http://localhost:8000` returned HTTP 200 ✅

**Revision rule:**
- Hicks is locked out for the next revision cycle. The next fix needs explicit proof at the rendered/update seam, not more helper-only tests.

# Review of commit 1de6fc9 — missing year header seam

- **Date:** 2026-05-16
- **Owner:** Vasquez
- **Commit:** `1de6fc9`
- **Verdict:** APPROVED
## Why

The backend seam is now explicit in `src/Backend.elm`: `listGroupTransactionsPage` passes `response.before` into `groupTransactionPageItems`, and that helper emits a `GroupTransactionYearSummary` when the first returned slice belongs to a different year than the cursor. That is the exact missing-header seam for `2026-01 -> 2025-12`, where page 2 enters 2025 before reaching 2025's boundary month.

The proof is no longer cosmetic. `tests/BackendTests.elm` now adds the missing second regression shape: page 1 contains only `2026-01`, page 2 starts at `2025-12/11`, and the assertions verify `Y 2025` is present both in the backend payload and after merging via `Frontend.groupTransactionsFromBackend`. The earlier regression that still shows a later `Y 2024` on the same page remains in place, so together the tests prove 2025 is not skipped in either adjacent boundary shape.
## Validation

- `lamdera make src/Frontend.elm --output=/dev/null` ✅
- `lamdera make src/Backend.elm --output=/dev/null` ✅
- `npm test` ✅
