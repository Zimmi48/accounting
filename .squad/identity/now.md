updated_at: 2026-05-15T15:58:18Z
focus_area: Fixing paginated transaction reload state before any migration regeneration
active_issues:
  - Preserve the number of loaded transaction pages across transaction-list reloads after adding or editing a spending
  - Remove the currently generated migration and leave regeneration for an explicit later user request
---

# What We're Focused On

Current work is fixing a new regression from incremental transaction loading: when the app reloads the current group's transactions after adding or editing a spending, it forgets how many pages were already loaded and jumps back to a newer slice of history. The implementation may change the model, but the currently generated migration should be deleted and left unregenerated until the user explicitly asks for migration work after reviewing the code changes.
