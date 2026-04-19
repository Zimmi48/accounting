# Squad Decisions

## Active Decisions

### Model-Only Spending/Transaction Split (2026-04-20)

**Status:** Approved for user review.

**Decision:** Keep the spending/transaction split in a compile-first intermediate state: spendings are stored separately from dated transactions, backend edit/delete works at the spending level, and the current dialog remains a singleton transaction adapter.

**Validation:**
- Model split in `src/Types.elm`: `spendings` separated from dated `transactions` with explicit `SpendingId`/`TransactionId` references
- Frontend/backend seams aligned: `CreateSpending`, `EditSpending`, `DeleteSpending`, `RequestSpendingDetails`, `SpendingDetails`, `SpendingError`
- Codec parity clean: `./check-codecs.sh` passed
- Compile targets pass: `lamdera make src/Frontend.elm` ✅, `lamdera make src/Backend.elm` ✅
- Development server responds: `lamdera live` → HTTP 200 ✅
- No Evergreen migration generated

**Constraint:** Do not generate Evergreen migration files until Théo reviews and accepts the model changes.

**Next Phase:** Phase 2 can expand the dialog to edit multiple transaction buckets once the model is approved.

### Phase 2 Contract Correction (2026-04-21)

**Status:** Approved and implemented.

**Decision:** Phase 2 spending/transaction split is now complete and validated:
- **Spending owns total invariant:** `total credits = total debits = spending.total` enforced at spending scope (not bucket scope).
- **Transaction lines own dates:** Each credit/debit line has its own (year, month, day).
- **Transaction lines own secondary descriptions:** Each credit/debit line can have optional secondaryDescription.
- **Spending date is UI default seed:** When adding new lines, pre-fill dates with spending date.
- **SpendingTransaction remains ID-free:** Wire format unchanged; backend assigns TransactionId after insertion.

**Implementation stack (approved):**
- Hudson commit `b7d0444`: Restored spending-level invariant in `src/Backend.elm`.
- Bishop commit `862817b`: Refreshed codec parity in `src/Codecs.elm`.

**Validation:**
- Compiler: `lamdera make src/Frontend.elm` ✅, `lamdera make src/Backend.elm` ✅
- Formatting: `elm-format --validate src/` ✅
- Codecs: `./check-codecs.sh` ✅
- Development server: `lamdera live` → HTTP 200 ✅
- No Evergreen migration generated (deferred pending data model finalization)

**Constraint:** Do not generate Evergreen migration files until Théo reviews and accepts any backend `Spending` and `Transaction` record changes.

**Next Phase:** Phase 2 dialog expansion can proceed to multi-bucket editing once this contract is committed.

### UI Lightweight Refinement (2026-04-21)

**Status:** Approved and implemented.

**Decision:** Refine the approved spending editor frontend to be lighter while preserving the contract:
- Collapse per-line date and secondary-description fields by default.
- Auto-show (expand) those fields whenever the secondary description is non-empty OR the line date differs from the spending date.
- Restore debitors-before-creditors rendering order (debits first, then credits).
- No backend or wire-format changes; `SpendingTransaction` remains ID-free and contract-correct.

**Implementation stack (approved):**
- Hicks commit `6d0a983`: Refined `src/Frontend.elm` spending editor UI.

**Validation:**
- Compiler: `lamdera make src/Frontend.elm` ✅, `lamdera make src/Backend.elm` ✅
- Formatting: `elm-format --validate src/` ✅
- Codecs: `./check-codecs.sh` ✅
- Development server: `lamdera live` → HTTP 200 ✅

**Constraint:** Frontend-only refinement. No changes to `SpendingTransaction` shape, `CreateSpending`/`EditSpending` payloads, or backend behavior. Reveal/collapse state is session-local and does not persist.

**Next Phase:** Dialog can be further expanded to multi-bucket editing once main-branch integration is complete.

### UI Icon Polish (2026-04-21)

**Status:** Approved and implemented.

**Decision:** Refine the spending editor frontend with focused UI polish:
- Remove bold row styling; move row identity to inline group-field labels (`Debitor 1`, `Creditor 1`, etc.)
- Reorder revealed detail fields to show `Description` before `Date`
- Replace rough disclosure/remove glyphs with clean inline SVG controls (`strokedIcon`, `detailsCollapsedIcon`, `detailsExpandedIcon`, `removeIcon`)
- Reject `agj/elm-simple-icons` as unsuitable: package provides brand/project logos, not generic disclose/remove semantics

**Implementation stack (approved):**
- Hicks commit: Polished `src/Frontend.elm` spending editor

**Validation:**
- Compiler: `lamdera make src/Frontend.elm` ✅, `lamdera make src/Backend.elm` ✅
- Formatting: `elm-format --validate src/` ✅
- Development server: `lamdera live` → HTTP 200 ✅

**Constraint:** Frontend-only refinement. No changes to `SpendingTransaction` shape, payloads, backend behavior, or approved contract. Debitors continue to render before creditors. Ready first row, one trailing placeholder, and empty-row pruning preserved.

**Reviewer:** Vasquez approved. Verified all requirements met and contract upheld.

### UI Row Width Fixes (2026-04-22)

**Status:** Approved and implemented.

**Decision:** Fix spending dialog row width contract consistency:
- Treat spending total edits as parent-level changes only; do not auto-fill debit/credit line amounts
- Use identical breakpoint-aware width split for both compact first row and revealed detail row
  - Desktop: one flexible text field + one compact 150px field
  - Small screens: paired fields split available width evenly

**Implementation stack (approved):**
- Hicks commit `5eab7a5`: Fixed row width consistency in `src/Frontend.elm`

**Validation:**
- Compiler: `lamdera make src/Frontend.elm` ✅, `lamdera make src/Backend.elm` ✅
- Formatting: `elm-format --validate src/` ✅
- Codecs: `./check-codecs.sh` ✅
- Development server: `lamdera live` → HTTP 200 ✅

**Constraint:** Frontend-only refinement. No changes to `SpendingTransaction` shape, payloads, or backend behavior. Preserves all approved editor contract behaviors (ready first row, trailing placeholder, debitors before creditors, inline group labels, hidden details by default).

**Reviewer:** Vasquez approved. Verified all requirements met and no regressions against approved contract. PR #39 ready for merge.

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction


### UI Final Fixes (2026-04-22)

**Status:** Approved and implemented.

**Decision:** Fix spending-editor UI seams in committed frontend:
- Disable auto-fill: editing one debitor/creditor row no longer seeds the untouched opposite side (debit ↔ credit balance preserved by read-only peer)
- Match layout widths: `Date + field` block wrapper width equals `Amount + field` block wrapper width, inner controls fill equally

**Implementation stack (approved):**
- Hicks commit `ae26ce6`: Fixed row normalization and layout width in `src/Frontend.elm`

**Validation:**
- Formatter: `elm-format --validate src/` ✅
- Codecs: `./check-codecs.sh` ✅
- Compiler: `lamdera make src/Frontend.elm` ✅, `lamdera make src/Backend.elm` ✅
- Development server: `lamdera live` → HTTP 200 ✅

**Constraint:** Frontend-only refinement. No changes to `SpendingTransaction` shape, payloads, or backend behavior. All previously approved editor contracts preserved (ready first row, trailing placeholder, debitors before creditors, inline labels, hidden details by default, description before date, spending-level invariant).

**Reviewer:** Vasquez approved. Verified both fixes present and no regressions. PR #39 ready for merge.

**Next Phase:** Main-branch integration complete. Phase 2 multi-bucket editing expansion can proceed.
