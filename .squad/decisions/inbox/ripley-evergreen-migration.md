# Evergreen V26 migration boundary

## Context
The authorized `v24 -> v26` Lamdera migration changes persisted backend storage from `Day.spendings : List Spending` to a split model with top-level `BackendModel.spendings : Array Spending` and per-day `Day.transactions : Array Transaction`. Old frontend dialogs, group listings, and in-flight messages still identify records with legacy `TransactionId` values, while the new runtime contract needs `SpendingId` for edit/delete/detail flows.

## Decision
1. Preserve backend accounting history exactly by rebuilding both new storage surfaces from the old day-local spendings in one chronological pass.
2. Derive new `SpendingId`s from append-only migration order and derive `transactionIds` from per-day append-only slot order so durable references remain coherent after deploy.
3. Rebuild `groupMembersKey` / `groupMembers` from legacy groups and persons during migration instead of defaulting them away.
4. Reset unverifiable frontend-only state and legacy edit/delete/detail messages to safe no-ops rather than fabricate `SpendingId`s that could target the wrong spending.

## Why
The backend has enough persisted information to reconstruct the new model without data loss. The frontend migration surface does not: a bare legacy `TransactionId` does not encode the global array position needed for the new `SpendingId`, so guessing would risk silent destructive edits.

## Key files
- `src/Evergreen/Migrate/V26.elm`
- `src/Evergreen/V24/Types.elm`
- `src/Evergreen/V26/Types.elm`
- `src/Backend.elm`
- `src/Frontend.elm`
