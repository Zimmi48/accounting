# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Group expense and accounting app with shared types across frontend and backend.
- **Created:** 2026-04-19

## Learnings

- Initial roster assignment: Lead for cross-cutting changes, migrations, and review.
- **Spending model architecture (V24)**: `BackendModel.years` is a `Dict Int Year` → `Dict Int Month` → `Dict Int Day` → `List Spending` hierarchy. Each level carries `totalGroupCredits` for aggregation. Spendings are append-only with soft-delete via `TransactionStatus` (Active/Deleted/Replaced). `TransactionId = { year, month, day, index }` locates a spending by its position in `Day.spendings`.
- **Duplicate merging**: On spending submit, `Dict.fromListDedupe (+)` in Frontend.elm merges credits/debits with the same group name. This is the only dedup — no date/description grouping exists yet.
- **Edit flow**: `EditTransaction` marks old spending as `Replaced`, creates a new `Spending` record (possibly at a different date). `DeleteTransaction` marks as `Deleted`. Both adjust `totalGroupCredits` aggregations. The pattern is "mark old + create new" — never mutate in place.
- **Codecs**: Auto-generated via `./check-codecs.sh --regenerate` using elm-review-derive. `amountCodec` is manually maintained due to phantom type. CI verifies codec freshness.
- **Evergreen migrations**: Latest is V24. Migrations live in `src/Evergreen/Migrate/`. Backend model was `ModelUnchanged` in V24 migration (only frontend changed for Theme support).
- **Key files**: `src/Types.elm` (all shared types), `src/Backend.elm` (~780 lines, all backend logic), `src/Frontend.elm` (~1960 lines, full frontend), `src/Codecs.elm` (serialization), `src/Evergreen/V24/Types.elm` (latest snapshot).
- **User preference**: Théo wants the spending/transaction split phased — model correctness first, UI expansion second. Confirmed spendings are the editable/deletable unit; transactions are the viewable unit in group lists.
- **Decision written**: `ripley-spending-transaction-split.md` — full plan for the model split including types, migration, backend, frontend, sequencing, and risk assessment.
- **Stalled revision triage (2026-04-19)**: Hicks' revision of the spending/transaction split was stuck with 12+ compile errors. Root cause: phase mixing (attempted Phase 2 UI changes before Phase 1 compiled) and agent/task mismatch (Hicks is frontend-only, task is full-stack). Codecs were cross-wired between Spending and Transaction types. No Evergreen migration created. Decision: relieve Hicks, discard worktree, launch fresh revision with general-purpose agent. Bishop remains locked out per reviewer protocol. Written to `ripley-stalled-revision-triage.md`.
- **Elm codec pitfall**: `Codec.object` in elm-codec applies fields positionally to the record constructor. If field order in the codec doesn't match the record definition order, values silently go to wrong fields. Always verify codec field order matches the type alias field order.
- **Phase discipline matters**: Cross-cutting changes that touch Types + Backend + Frontend + Codecs must compile at every intermediate step. Never layer Phase 2 features before Phase 1 compiles. The cascade of missing definitions becomes unrecoverable faster than expected.
- **Phase 1 compile-first split (2026-04-19)**: `src/Types.elm` now separates durable `SpendingId` and `TransactionId`, stores spendings in `BackendModel.spendings`, and stores dated `Day.transactions` with bidirectional references (`Spending.transactionIds`, `Transaction.spendingId`).
- **Phase 1 backend behavior**: `src/Backend.elm` now normalizes submitted transaction buckets by `(year, month, day, secondaryDescription)`, merges credits and debits separately per group inside each bucket, keeps append-only replace/delete semantics, and blocks multi-transaction spending edits until the Phase 2 dialog exists.
- **Phase 1 frontend contract**: `src/Frontend.elm` still uses the existing spending dialog, but it now edits/deletes by `SpendingId` while listed rows stay transaction-based; submits send a singleton default transaction bucket with the selected date and empty secondary description.
- **Codecs status**: `src/Codecs.elm` was updated manually for the new backend shape because the derive-based regeneration path did not produce a usable backend codec in this environment; field order still matches the type constructors.

## Learnings (2026-04-20)

- **Phase 2 contract correction (2026-04-20)**: User clarified that bucket-level totals were incorrect. The invariant should be at spending scope (total credits = total debits = stated total). Each transaction line should carry its own date and optional secondary description. Spending date is a UI default for convenience, not a data constraint. Wrote detailed contract to `ripley-phase2-contract-correction.md` covering: remodeled dialog (spendingDate, spendingTotal, transactionLines), backend validation shift to spending scope, deferred Evergreen migration for Transaction.total removal, and open questions for UX refinement. Decision: no code changes until contract approval.
- **Bucket-total enforcement pattern**: Backend `transactionBucketKey = (year, month, day, secondaryDescription)` groups transactions into buckets for aggregation. `transactionBucketTotals` and `transactionBucketMetadata` compute per-bucket totals and store them in Transaction records. This is a mechanical reusable pattern but conflates UI grouping (buckets as a convenience) with data invariants (totals as a constraint). The user correction separates them: buckets are display/edit grouping only; invariant is spending-scoped.
- **Migration safety for stored fields**: Removing `Transaction.total` requires Evergreen migration because it is persisted in the backend. Options: (1) Remove entirely + migrate, (2) Repurpose for spending total + migrate, (3) Keep but ignore + fragile. Recommendation: option (1) after user approval. Migration logic: group old transactions by bucket, sum to get spending total, store in new `Spending.total` field.
- **Frontend dialog modeling**: Current `TransactionBucket` separates date, description, total, and lists of (group, amount, validity) tuples per side. Corrected model flattens to `TransactionLine` (one per visible row) with individual date, description, group, amount, side. Dialog state complexity increases: more form fields, more update messages, more validation hooks. No new types strictly required, but struct design matters for handler clarity.

## 2026-04-21: Phase 2 Contract Correction Approved

- **Session timestamp:** 2026-04-21T06:49:24Z
- **Contract locked:** User directive captured and implemented by Hudson + Bishop
- **Spending-level invariant:** Backend now enforces `total credits = total debits = spending.total` after normalization
- **Per-line ownership:** Dates and optional secondary descriptions stored at transaction level
- **Spending date role:** UI default seed only, not a data constraint
- **ID-free wire format:** `SpendingTransaction` remains free of embedded transaction IDs
- **Next phase:** Data model finalization and Evergreen migration planning await user approval

