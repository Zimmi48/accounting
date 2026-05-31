# Project Context

- **Owner:** Théo Zimmermann
- **Project:** Accounting group-expense Lamdera application
- **Stack:** Elm, Lamdera, elm-test
- **Created:** 2026-05-17T00:00:00Z

## Learnings

- 2026-05-17: Frontend regression coverage for progressive group transactions lives in `tests/FrontendTests.elm`, mostly through pure helpers such as `groupTransactionsViewportLoadMorePlan` and `toggleGroupTransactionMonthFoldPlan`.
- 2026-05-17: Dialog-open interaction coverage can prove that month/year pagination plans still trigger while `showDialog` is populated, but actual browser scroll-through behavior still depends on a view-level seam in `src/Frontend.elm`.

## 2026-05-31: Dialog + Grouped Transaction Regression Coverage

**Assignment:** Add/read regression coverage for dialog + grouped transaction list behavior.

**Task:** Validate message/planning contract for progressive transaction loading with open dialog; ensure bottom-of-list load-more planning emits `RequestGroupTransactions`; verify month-fold toggles request viewport recheck when dialog is open; align test coverage with Dallas's dialog-mask scroll implementation.

**Test Coverage Implementation:**
- Dialog preservation: Opening a dialog must not remove `groupTransactionsViewportId` scroll container
- Scroll routing: Dialog mask blocks pointer clicks; wheel/touch scrolling routes into transaction list; dialog-mask scroll plan computes correct viewport target
- Progressive loading consistency: Bottom-of-list scrolling requests next page while dialog open; month/year summaries stay ordered across load-more; fold state preserved
- Month fold + dialog interaction: Folding with dialog open re-checks viewport; load-more triggers if fold exposes list end; pagination path reused

**Implementation Details:**
- Leverages pure helpers: `groupTransactionsDialogMaskScrollPlan`, `groupTransactionsViewportLoadMorePlan`, `toggleGroupTransactionMonthFoldPlan`
- No opaque Cmd assertions; pure seam testing
- Aligns with Dallas's Frontend implementation

**Validation:**
- ✅ elm-format src/ tests/ --yes
- ✅ npm test
- ✅ All regression cases pass

**Outcome:** ✅ Dialog + grouped transaction regression coverage complete; seam assertions prove scroll routing, progressive loading, and fold interaction all work together safely.

**Decision recorded:** Dialog + Grouped Transaction Regression Coverage (`.squad/decisions.md`, 2026-05-31)

**Orchestration log:** `.squad/orchestration-log/2026-05-31T14:17:51Z-hockney.md`
