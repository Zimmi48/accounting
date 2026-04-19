---
name: "stored-id-stability"
description: "Detecting and fixing stored positional-ID instability in append-only list stores"
domain: "architecture"
confidence: "high"
source: "earned"
---

## Context

When a system uses positional indices as identifiers (e.g., `index` in a list), those indices must be computed under the same insertion semantics they will later be resolved under. If index assignment assumes append semantics but the actual insertion is prepend (or vice versa), stored IDs will map to the wrong records from the moment they are written.

This is only a latent issue when IDs are derived at read-time (ephemeral). It becomes an active bug the moment IDs are **stored** — because stored IDs must survive list mutations.

In this codebase, the regression was introduced when `Spending.transactionIds : List TransactionId` was added to store durable references from spending to transaction records. `assignTransactionIds` computed indices from `dayTransactionCount` (an append-position model), but `addTransactionToDay` prepended. The IDs were wrong from the moment of creation.

## Patterns

### Rule: index-assignment semantics must match insertion order

- If index = current list length → new item must be **appended** (goes to that exact position)
- If index = 0, decrementing → new item must be **prepended**
- If using a monotone counter not tied to list length → use `Dict` keyed by that counter, not a `List`

### Rule: prefer back-references over forward-references for membership

When a parent record (Spending) needs to know which child records (Transactions) belong to it, prefer having each child carry a `parentId` field rather than having the parent carry a list of `childIds`.

- Child's `parentId` is set at creation, immutable, and cannot drift with list mutations.
- Parent's `childIds` is a computed denormalization of the same information, but must be kept in sync across all insertions, and relies on stable positional lookups.

In Elm/Lamdera with append-only soft-delete stores: **child-to-parent back-reference is the canonical source of truth**.

### Detection checklist

When reviewing code that stores positional IDs:

1. Find where the ID's `index` is assigned (the allocator).
2. Find where the new record is inserted into the list (the inserter).
3. Verify: `index = list.length` → inserter must append. `index` is some other scheme → inserter must be consistent with it.
4. Find where `findById` resolves the stored ID → confirm it uses the same traversal order as both (1) and (2).
5. If anything is inconsistent, flag as data-integrity bug, not just display bug — check whether ID resolution is used in aggregate rollback paths.

### The "derive at read-time" principle

If stored IDs are not strictly necessary, consider deriving the relationship at read-time instead of storing it. In this codebase: `getSpendingTransactions` can be rewritten to filter `transaction.spendingId == spendingId` instead of following stored `Spending.transactionIds`. The filter uses an immutable, creation-time back-reference, which cannot drift.

## Examples

**Bug pattern — prepend insertion with append-style index:**
```elm
-- Index assigned as: List.length existingList → expects append position N
assignedIndex = List.length day.transactions  -- e.g. 2

-- But insertion prepends:
{ transactions = newTransaction :: day.transactions }  -- new item at position 0!

-- Later lookup:
listGet 2 [new, old0, old1]  -- returns old1, not new
```

**Fix — append instead:**
```elm
{ transactions = day.transactions ++ [ newTransaction ] }  -- new item at position 2 ✓
```

**Alternative fix — use back-reference scan:**
```elm
getSpendingTransactions spendingId model =
    Dict.values model.years
        |> List.concatMap (.months >> Dict.values)
        |> List.concatMap (.days >> Dict.values)
        |> List.concatMap .transactions
        |> List.filter (\t -> t.spendingId == spendingId)
-- No stored transactionIds needed. transaction.spendingId is immutable.
```

## Anti-Patterns

- **Do not** mix append-style index allocation with prepend insertion.
- **Do not** store redundant parent-to-child ID lists when child-to-parent back-references are already persisted. Redundancy creates two representations that can drift.
- **Do not** classify a stored-ID mismatch as a "display-only bug." Any code path that uses the mismatched ID for aggregate rollback (credits, debits, totals) corrupts persistent state silently.
- **Do not** "fix" a positional-ID bug by adding a secondary match (e.g., matching on group name) as a tiebreaker. That guesses at the correct record rather than resolving it reliably.
