# Project Context

- **Owner:** Théo Zimmermann
- **Project:** accounting
- **Stack:** Elm, Lamdera, elm-ui, elm-review, elm-format
- **Description:** Full-stack group expense and accounting app with shared models, backend logic, and Elm UI.
- **Created:** 2026-04-20

## Learnings

- Joined to own the post-model-review cleanup pass after prior authors were locked out on the spending/transaction split artifact.
- User directive: do not generate the Evergreen migration before Théo reviews the model changes.
- For the model-only spending/transaction split, the review seam is codec alignment: `src/Codecs.elm` and `src/Codecs.elm.stub` must stay in sync with `src/Types.elm`, and `./check-codecs.sh` is the fastest gate.
- This cleanup cycle confirmed the current worktree is already in the compile-first review state: no new `src/Evergreen/` migration files were needed, while `elm-format --validate src/`, `./check-codecs.sh`, both `lamdera make` targets, and `lamdera live` with HTTP 200 all passed.
- `2026-04-20T16:43:52Z`: Model-only spending/transaction split approved for user review

- 2026-04-20: Corrected model pass keeps `TransactionId` as `{ year, month, day, index }`, expands each logical spending bucket into one-sided dated transactions, reconstructs single-bucket spending details for the current dialog, and still defers any Evergreen migration until after user review. Key paths: `src/Types.elm`, `src/Backend.elm`, `src/Codecs.elm`, `src/Codecs.elm.stub`.

- 2026-04-20: Corrected Array target after commit `e64d99e` misread the user request. User asked for Array storage for **spendings**, not for Day.transactions. Changed `BackendModel.spendings` from `Dict SpendingId Spending` to `Array Spending`, and reverted `Day.transactions` from `Array Transaction` back to `List Transaction`. Updated all related code paths and codecs. All validation gates passed with no new Evergreen files. The branch now correctly implements both user directives: Amount wrapper for transaction amounts, and Array storage for spendings.

### 2026-04-21: Phase 2 Contract Correction Approved

- **Session timestamp:** 2026-04-21T06:49:24Z
- **Approved commits:** Hudson `b7d0444` (spending-level invariant) + Bishop `862817b` (codec parity)
- **Final verdict:** All review gates pass. Contract confirmed and locked.
- **Next phase:** Awaiting user approval of any backend record changes before Evergreen migration.
- **Team coordination:** Ripley clarified contract, Hudson restored invariant, Bishop refreshed codecs, Vasquez approved stack.

