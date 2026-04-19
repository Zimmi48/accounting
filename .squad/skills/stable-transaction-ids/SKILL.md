---
name: "stable-transaction-ids"
description: "How to keep Lamdera transaction references stable when storage uses append-only records and day buckets"
domain: "data-modeling"
confidence: "high"
source: "earned"
---

## Context
This applies when the app still needs exact transaction-level addressing after splitting one logical spending into multiple stored day rows. In this repo, `TransactionId` is a `{ year, month, day, index }` day-slot reference, `Day.transactions` is append-only storage, and a spending may still persist `transactionIds` when direct parent-to-children lookup is a required contract.

## Patterns
- If an id is persisted inside records, resolve by the stored id value, not by current container position.
- Positional ids are only safe when they are regenerated from the current list each time and never stored as durable cross-record references.
- For append-only arrays, derive the next record id from `Array.length` instead of storing a separate redundant counter.
- Treat array-index identity as safe only when the collection is append-only and never compacted, re-sorted, or inserted into by position.
- If a record already lives inside unique parent buckets (for example `Year -> Month -> Day -> Array Transaction`), do not duplicate those bucket coordinates inside the stored record unless another persistence boundary truly needs them.
- If exact row addressing is still needed but the store is truly append-only, keep the positional id ephemeral: append writes, derive `{ year, month, day, index }` from traversal context on read, and use immutable back-references like `transaction.spendingId` for membership.
- If product requirements still demand spending-owned transaction membership, store `Spending.transactionIds`, assign those ids before append-only writes using current bucket lengths, and resolve spending transactions by targeted bucket lookup rather than whole-model scans.
- Under a no-migration rule, a legacy persisted id/counter field can stay in the storage shape as a compatibility mirror even if newer runtime logic no longer needs it. In that case, keep the legacy field populated consistently with the append-only write path so exports and saved state remain decodable without Evergreen work.

## Examples
- `src/Backend.elm`: `createSpendingInModel` uses `Array.length model.spendings` for the next `SpendingId`.
- `src/Backend.elm`: `assignTransactionIds` computes the future `{ year, month, day, index }` values from current day counts before inserts, `addTransactionToDay` appends with `Array.push`, and `getSpendingTransactionsWithIds` follows `Spending.transactionIds` straight to `findTransaction`.
- `src/Types.elm`: `Spending.transactionIds` stores the direct lookup list, while stored `Transaction` still keeps `spendingId` as the back-reference.

## Anti-Patterns
- Do not persist a day-list index and later treat it as the current list position after insertions can reorder that list.
- Do not keep a `next*Id` counter when the underlying append-only structure already determines the next id.
- Do not assume switching from `List` to `Array` removes identity requirements; it often only moves the durable reference into parent records or traversal context.
- Do not keep both append-only positional ids and stored per-row ids unless two different identity contracts are actually required.
- Do not recover a known spending's transactions by flattening the whole model and filtering when a maintained `transactionIds` list already exists.
