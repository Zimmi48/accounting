---
updated_at: 2026-05-02T14:09:09Z
focus_area: Refactoring group-scoped transaction storage and stable IDs
active_issues:
  - Move transaction years and aggregate credits under groups instead of a single global years dictionary
  - Introduce numeric group IDs from the same ID space as persons and include group ID in TransactionId
  - Hold Evergreen migration work until the user reviews and validates the code changes
---

# What We're Focused On

Current work has shifted to a backend/shared-model refactor: transactions and aggregate credits should be stored per group, group IDs should become numeric stable identifiers in the same ID space as persons, and TransactionId should expand to include the owning group ID. Do not generate or write the Evergreen migration yet; wait for user review and validation of the code changes first.
