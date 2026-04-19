# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Full-stack group expense and accounting app with shared models, backend logic, and Elm UI.
- **Created:** 2026-04-20

## Learnings

- Joined to own the correction that makes each transaction one-sided for exactly one group.
- User directive: do not generate the Evergreen migration before Théo reviews the model changes.
- Current reviewable intermediate state keeps `TransactionId` as `{ year, month, day, index }` and defers Evergreen generation until after user review.
- The one-sided transaction fan-out now happens before persistence: `src/Frontend.elm` emits one record per group/side, while `src/Backend.elm` rebuilds bucket totals and group-members metadata from date/description keys.
- Key paths for this pass: `src/Types.elm`, `src/Backend.elm`, `src/Frontend.elm`, `src/Codecs.elm`, and `.squad/decisions/inbox/dallas-one-sided-transactions.md`.

- Phase 2 correction: `Spending.total` now owns the invariant, while `Transaction` keeps only one-sided line data and `src/Backend.elm` validates `credits = debits = spending total`.
- Spending editor pattern: `src/Frontend.elm` keeps a dialog-level default date, but every credit/debit line now owns its own date and optional secondary description fields.
- Codec impact for this correction stayed in `src/Codecs.elm`; no new `src/Evergreen/` files were generated during the fix-forward pass.

## 2026-04-21: Pre-tweak Checkpoint Commit

**Commit:** ddb8cb7 "Refactor: One-sided transactions with explicit spending records"

**Task:** Create a checkpoint commit for the approved one-sided transaction state before any further model tweaks.

**Committed files:**
- Core model: `src/Types.elm`, `src/Backend.elm`, `src/Frontend.elm`, `src/Codecs.elm`, `src/Codecs.elm.stub`
- Squad context: `.squad/agents/`, `.squad/casting/`, `.squad/routing.md`, `.squad/team.md`, `.squad/skills/`

**Excluded files:**
- `.squad/templates/workflows/*` — these are existing squad infrastructure files, not related to the one-sided transaction work
- `.squad/decisions/inbox/` — gitignored by design for local-only decision drafts

**Key pattern:** When committing model work, include the squad agent histories and skill files that document the architectural decisions, but exclude unrelated infrastructure additions.

## 2026-04-21: Amount Wrapper and Array Refinement

**Commit:** e64d99e "Refactor: Use Amount wrapper and Array for transactions"

**Task:** Apply two model refinements:
1. Wrap transaction amounts in `Amount ()` instead of raw `Int`
2. Change `Day.transactions` from `List` to `Array` for efficiency

**Implementation approach:**
- Used `Amount ()` (unit phantom type) for transaction amounts since the `side` field already provides credit/debit semantics
- Updated Backend operations: `Array.get` for indexing, `Array.push` for appends, `Array.map` for transforms, `Array.toList` for iteration
- Pattern-matched `Amount` constructors throughout to extract/wrap integer values
- Frontend changes minimal: just wrap amounts when building SpendingTransaction records
- Codecs auto-regenerated via `./check-codecs.sh --regenerate`

**Key insight:** Transaction-level amounts don't need phantom type tracking (Credit/Debit) because the explicit `side` field carries that information. The `Amount ()` wrapper satisfies the "use Amount" requirement without complicating type signatures across the hierarchy.

**Validation:**
- Both `lamdera make src/Frontend.elm` and `lamdera make src/Backend.elm` compiled successfully
- `lamdera live` started and responded with HTTP 200
- No Evergreen migration files generated (as required)

**Follow-on implications for Phase 2:**
- The Array storage preserves append-only ordering and stable indexing via `TransactionId.index`
- SpendingTransaction now explicitly carries `Amount ()`, so Phase 2 multi-bucket UI will handle amounts consistently
- All aggregate calculations continue to use phantom-typed `Amount Credit`/`Amount Debit` at the bucket/group level

## 2026-04-21: Phase 2 Contract Correction Approved

- **Session timestamp:** 2026-04-21T06:49:24Z
- **Final verdict:** Current HEAD `862817b` (Hudson + Bishop) approved by Vasquez
- **Contract confirmed:** Spending owns total invariant; transaction lines own dates/secondary descriptions
- **Backend validation:** `validateSpendingTransactions` now enforces spending-level invariant
- **Frontend behavior:** Dialog shows spending date as default seed for new transaction lines
- **ID-free payload:** `SpendingTransaction` remains free of embedded transaction IDs
- **Validation gates:** elm-format, codecs, both lamdera makes, HTTP 200 all pass
- **Next work:** Await data model finalization for Evergreen migration planning

