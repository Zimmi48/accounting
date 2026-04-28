---
name: "evergreen-migration-review"
description: "How to review Lamdera Evergreen migrations that mix generated artifacts with manual state reshaping"
domain: "review"
confidence: "high"
source: "earned"
---

## Context
Use this when Lamdera persistence changes are finally authorized and `lamdera check --force` generates a large migration skeleton. It is especially important when the old Evergreen model and the new runtime model store the same business facts in different places, because compile success can hide silent data loss.

## Patterns
- Treat the migration as two deliverables: a pure generated-artifacts commit first, then a separate manual-migration commit.
- Inspect the previous Evergreen type module and the new Evergreen type module side by side before trusting any generated default.
- Count and eliminate every `Unimplemented` placeholder in `src/Evergreen/Migrate/*.elm`; no placeholder is harmless.
- When storage moves from nested records to top-level arrays (or the reverse), verify that old persisted data is reconstructed, not defaulted away.
- Preserve durable cross-record references (`Spending.transactionIds`, append-only slot ids, status flags) and check that migrated references still point at the migrated records.
- Require a final `lamdera check --force` after manual edits, in addition to normal tests/builds, so the Evergreen set is internally coherent.

## Examples
- In this repo, `src/Evergreen/V24/Types.elm` stores spendings under `Day.spendings`, while `src/Evergreen/V26/Types.elm` expects top-level `BackendModel.spendings : Array Spending` and `Day.transactions : Array Transaction`; a migration that sets either array to empty would drop accounting history.
- `src/Evergreen/Migrate/V26.elm` was auto-generated with 39 `Unimplemented` placeholders, so review must reject any implementation that leaves even one unresolved or hides manual logic inside the initial generated commit.

## Anti-Patterns
- Do not approve a migration because `npm test` and `lamdera make` pass; those do not prove persisted-state safety.
- Do not mix generated output and handwritten migration logic in one commit when the review plan depends on separating them.
- Do not use placeholder defaults (`Array.empty`, `Nothing`, dummy ids) for data that already exists in the old Evergreen model unless a documented safe reset is truly intended.
