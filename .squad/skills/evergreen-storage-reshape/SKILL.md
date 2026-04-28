---
name: "evergreen-storage-reshape"
description: "Implement Lamdera Evergreen migrations when persisted storage moves across record boundaries"
domain: "migration"
confidence: "high"
source: "earned"
---

## Context
Use this when Lamdera changes where durable data lives, such as moving records from nested day buckets into a top-level array plus per-day child arrays. The generated migration skeleton will not know how to preserve cross-record references or how much frontend state can be migrated safely.

## Patterns
- Generate Evergreen files first, commit them untouched, then implement manual migration logic in a follow-up commit.
- Rebuild old storage and new storage together in one deterministic traversal so newly assigned ids and newly assigned array slots stay aligned.
- Preserve persisted facts exactly when the old backend model contains enough information; rebuild derived metadata instead of defaulting it away.
- If old frontend state or in-flight messages lack the context needed to recover a new durable identifier, reset that UI seam to a safe no-op rather than inventing ids.
- Prove storage-reshape safety with regression fixtures on both seams: backend tests should follow every migrated stored id back to the rebuilt row, and frontend tests should assert legacy transaction-addressed dialogs/messages are cleared or no-op'd.
- Finish with `lamdera check --force` plus the normal format/build/test/live validations.

## Examples
- `src/Evergreen/Migrate/V26.elm` now walks legacy `Day.spendings` chronologically, appends migrated spendings into `BackendModel.spendings`, and assigns matching per-day `TransactionId.index` slots for `Day.transactions`.
- The same migration rebuilds `groupMembersKey` and `groupMembers` from legacy `groups` and `persons`, but clears frontend `groupTransactions` and legacy edit/delete/detail messages because legacy `TransactionId` alone cannot determine a correct new `SpendingId`.

## Anti-Patterns
- Defaulting migrated backend arrays to `Array.empty` when the old persisted model already contains the source data.
- Fabricating `SpendingId`s for legacy frontend edit/delete flows without a backend-derived lookup.
- Treating `lamdera make` or `npm test` as sufficient proof that the Evergreen migration is safe.
