---
name: "export-semantic-diff"
description: "Compare Lamdera JSON exports across storage-shape changes without being distracted by structural churn"
domain: "migration-review"
confidence: "high"
source: "earned"
---

## Context

Use this when a Lamdera backend export changes storage layout between versions, but the review question is whether persisted meaning changed. In this repo, legacy exports store logical spendings directly under `Day.spendings`, while current exports split them between top-level `BackendModel.spendings` and per-day `Day.transactions`.

## Patterns

- Normalize both sides into the same semantic shape before diffing.
- Compare logical spendings by description, total, status, and dated line items rather than by raw array position or stored ids.
- Add a second projection for per-group active transaction lists, matching the app's `RequestGroupTransactions` behavior rather than the raw storage graph.
- For that projection, keep only active transactions whose owning spending is also active, then normalize each row to date, rendered description, spending total, and signed share (credits negative, debits positive).
- Mirror the full listing seam, not just the payload shape: preserve the backend traversal order, apply the frontend's newest-first reversal, and compare the ordered per-group rows as the user would see them.
- Ignore storage-only churn like `loggedInSessions`, raw `transactionIds`, and opaque `groupMembersKey` strings.
- Translate `totalGroupCredits` keys from person-id strings back into sorted person-name sets so totals can be compared semantically even if ids churn.
- Keep `nextPersonId` in the report because it affects future writes and collisions, even though most person-id usage is storage detail.
- Treat unresolved `transactionIds`, duplicate references, and spending/transaction status mismatches as integrity failures worth surfacing in the diff report.

## Examples

- `scripts/compare_exports.py` detects legacy vs current export formats, reconstructs logical spendings from either shape, and reports only semantic differences.
- `README.md` documents the intended workflow: export from production before migration, export again after migration, then compare with the script.

## Anti-Patterns

- Do not trust a raw JSON diff across a storage reshape.
- Do not compare `groupMembersKey` or `belongsTo` literally when the semantic question is whether the represented member set changed.
- Do not treat missing transaction references in the new export as mere noise; they indicate a broken migration seam.
