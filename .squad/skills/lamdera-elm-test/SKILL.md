---
name: "lamdera-elm-test"
description: "Initialize and run elm-test safely in this Lamdera repo"
domain: "testing"
confidence: "low"
source: "earned"
---

## Context

Use this when the repo needs Elm unit tests without breaking Lamdera's compiler expectations. In this project, Elm tests are managed through local npm metadata and must use Lamdera as the compiler.

## Patterns

- Install `elm-test` as a repo-local npm dependency and run it through `npm test` so CI and local agents share the same entrypoint.
- Initialize or repair the test harness with `elm-test init --compiler "$(which lamdera)"`; do not hand-edit `elm.json` to add test dependencies.
- Keep tests focused on exposed pure helpers and data invariants so they can run quickly without booting Lamdera.
- Document each test block with a short comment explaining the regression seam it protects.
- After changing code or test infrastructure, validate with `npm test` plus the existing Lamdera compile/live checks.

## Examples

- `package.json`: `npm test` shells out to `elm-test --compiler "$(which lamdera)"`.
- `tests/BackendTests.elm`: append-only slot stability and spending validation coverage.
- `tests/FrontendTests.elm`: amount parsing, submit gating, and debt summary coverage.
- `tests/CodecsTests.elm`: backend JSON round-trip coverage.
- `.github/workflows/build.yml`: installs npm deps and runs `npm test` in CI.

## Anti-Patterns

- Adding test dependencies to `elm.json` by hand.
- Running `elm-test` with plain `elm` in this Lamdera repo.
- Writing UI-only smoke tests when a faster pure-function regression test can prove the invariant directly.
