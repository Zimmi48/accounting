updated_at: 2026-05-05T19:33:18Z
focus_area: Fixing mixed-creditor spending creation regression
active_issues:
  - Reproduce and fix the regression preventing new spendings with mixed positive and negative creditors
---

# What We're Focused On

Current work is reproducing and fixing a regression that prevents creating a new spending when multiple creditors include both positive and negative amounts. The likely fault is in the backend spending-creation path, and the fix must land with regression coverage plus the repo's Lamdera and npm validation steps.
