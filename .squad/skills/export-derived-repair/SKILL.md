---
name: "export-derived-repair"
description: "Validate and safely repair derived fields in a Lamdera backend export without mutating canonical records"
domain: "data-repair"
confidence: "high"
source: "earned"
---

## Context

Use this when a Lamdera export contains denormalized or cached fields that can be recomputed from canonical persisted records, and you want an offline audit/fix path that does not change the underlying spendings or transactions.

## Patterns

- Treat spendings plus stored transactions as the source of truth; treat aggregate caches and membership indexes as derived fields.
- Recompute expected aggregates from active transactions whose owning spending is also active.
- Validate both lifecycle invariants (spending totals, active/inactive status alignment, spending-to-transaction references) and derived caches (root/year/month/day totals, `Person.belongsTo`).
- Keep fix mode explicit and safe: write a separate corrected export file rather than mutating the input in place.
- Limit automatic fixes to fields that are mechanically derivable. Report non-fixable linkage or canonical-record corruption for manual review.

## Examples

- `scripts/validate_totals.py` replays active transactions from the current `/json` export shape and rewrites only `totalGroupCredits` plus `persons.*.belongsTo`.
- `README.md` documents the intended workflow: export via `/json`, validate, optionally write a corrected copy, then re-import through `/import`.

## Anti-Patterns

- Auto-rewriting `spendings`, `transactionIds`, statuses, or transaction payloads just to make reports go green.
- Repairing caches from all active transactions without checking whether their owning spending is still active.
- Mutating the source export file in place by default.
