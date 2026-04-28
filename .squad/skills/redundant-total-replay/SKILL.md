---
name: "redundant-total-replay"
description: "How to regression-test redundant aggregate totals without over-constraining cleanup shape"
domain: "testing"
confidence: "high"
source: "earned"
---

## Context
Use this when the backend stores denormalized totals at multiple scopes (for example global/year/month/day dictionaries) and lifecycle operations can leave low-priority cleanup residue behind after replacements or deletions.

## Patterns
- Build fixtures that exercise add, edit, and delete in sequence, not isolated happy paths.
- Recompute aggregates from the canonical active records and assert those active snapshots exactly.
- For stored redundant totals, assert numeric invariants that must stay true across scopes: active amounts appear in the right global/year/month/day buckets, and stale replaced/deleted amounts are missing or zero.
- Include at least one same-period edit and one cross-period edit so both in-place replacement and moved-period behavior stay covered.
- Pair the aggregate test with a user-facing seam test (group listings or spending details) to distinguish bad storage cleanup from bad active-row filtering.

## Examples
- `tests/BackendTests.elm`: `recomputedTotalsSnapshot` remains the exact oracle for active rows.
- `tests/BackendTests.elm`: stored aggregate checks use `lookupGroupAmount`, `lookupBucketAmount`, and `missingOrZero` instead of full stored-vs-recomputed equality.

## Anti-Patterns
- Requiring stored aggregate dictionaries to match a filtered active-only recomputation when internal cleanup is known to be a separate follow-up seam.
- Checking only the final global total while ignoring year/month/day caches.
- Verifying only visible lists, which can stay correct while redundant totals silently drift numerically.
