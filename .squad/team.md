# Squad Team

> Lamdera Elm app for shared-expense accounting and debt tracking.

## Coordinator

| Name | Role | Notes |
|------|------|-------|
| Squad | Coordinator | Routes work, enforces handoffs and reviewer gates. Does not generate domain artifacts. |

## Members

| Name | Role | Charter | Status |
|------|------|---------|--------|
| Ripley | Lead | `.squad/agents/ripley/charter.md` | ✅ Active |
| Hicks | Frontend Dev | `.squad/agents/hicks/charter.md` | ✅ Active |
| Bishop | Backend Dev | `.squad/agents/bishop/charter.md` | ✅ Active |
| Newt | Full-Stack Dev | `.squad/agents/newt/charter.md` | ✅ Active |
| Hudson | Full-Stack Dev | `.squad/agents/hudson/charter.md` | ✅ Active |
| Dallas | Full-Stack Dev | `.squad/agents/dallas/charter.md` | ✅ Active |
| Vasquez | Tester | `.squad/agents/vasquez/charter.md` | ✅ Active |
| Scribe | Session Logger | `.squad/agents/scribe/charter.md` | 📋 Silent |
| Ralph | Work Monitor | — | 🔄 Monitor |

## Coding Agent

<!-- copilot-auto-assign: false -->

| Name | Role | Charter | Status |
|------|------|---------|--------|
| @copilot | Coding Agent | — | 🤖 Coding Agent |

### Capabilities

**🟢 Good fit — auto-route when enabled:**
- Bug fixes with clear reproduction steps
- Test coverage additions and flaky test fixes
- Small isolated Elm features with clear acceptance criteria
- Dependency and tooling maintenance
- Documentation and README updates

**🟡 Needs review — route to @copilot but flag for squad member PR review:**
- Medium-sized refactors following established patterns
- Well-defined data migrations
- Backend or frontend additions with explicit specs

**🔴 Not suitable — route to squad member instead:**
- Architecture and model design decisions
- Ambiguous UX or product scope
- Security-sensitive or permission-sensitive changes
- Cross-cutting changes requiring coordinated frontend/backend/migration work

## Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Full-stack group expense and accounting app with shared models, backend logic, and Elm UI.
- **Created:** 2026-04-19
