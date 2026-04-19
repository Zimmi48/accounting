# Accounting

A web application for managing group expenses and accounting, built with Elm and Lamdera.

## Features

- User and group management
- Expense tracking with automatic debt calculation
- Data import/export functionality
- Real-time synchronization using Lamdera

## Development

This project is built with [Lamdera](https://lamdera.com/), a platform for building full-stack [Elm](https://elm-lang.org/) applications.

### Prerequisites

- [Lamdera](https://lamdera.com/)
- `elm-format` to keep the code properly formatted at each commit
- `elm-review` for regenerating codecs (see below)
- `elm-test` for running the tests

### Building

To build and test the project locally:

```bash
npm ci
npm test
lamdera live
```

### Auto-Generated Codecs

The codecs in `src/Codecs.elm` are auto-generated from the types in `src/Types.elm` using [elm-review-derive](https://github.com/gampleman/elm-review-derive). The stub file `src/Codecs.elm.stub` contains type signatures with `Debug.todo ""` placeholders that elm-review-derive fills in.

Two codecs require manual maintenance:
- **`amountCodec`**: `Amount` has a phantom type parameter that elm-review-derive can't handle; provided in the stub
- **`sessionIdCodec`**: `Lamdera.SessionId` is opaque; the script automatically replaces it with `Codec.string`

To regenerate after changing types:

```bash
./check-codecs.sh --regenerate
```

CI automatically verifies the codecs match the auto-generated output.

### Transaction and spending IDs

Transaction and spending IDs are derived from their position in the datastructure (a global array for spendings and an array for each day for transactions). Therefore, the contract to respect is that these arrays can only be appended to, but never compacted. Removed or replaced transactions or spendings are marked as not being active anymore with `TransactionStatus`.

## Isolated DevContainer (Lamdera + Squad)

This repository includes a Dev Container at `.devcontainer/` so you can run Copilot/Squad in an isolated environment instead of directly on your host.

### What it installs

- Node.js 24 (base image)
- `lamdera`
- `elm-format`
- `elm-review`
- `copilot`
- `@bradygaster/squad-cli`
- GitHub CLI (`gh`) and the `github/gh-copilot` extension

### How to use

1. In VS Code, run **Dev Containers: Reopen in Container**.
2. Wait for the post-create setup to finish.
3. Authenticate inside the container:
	```bash
	gh auth login
	gh auth status
	lamdera login
	```
4. Verify tools:
	```bash
	lamdera --version
	squad --help
	gh copilot --help
	```
5. Run this app in-container:
	```bash
	lamdera live
	```

For Squad + Copilot usage, run commands from the container terminal. If your Copilot binary exposes `copilot` directly, use that; otherwise use `gh copilot`.

## Continuous Integration

The project uses GitHub Actions for continuous integration. The workflow automatically:

- Installs project-local npm dependencies
- Checks formatting with `elm-format`.
- Runs the Elm test suite with `npm test`
- Compiles both Frontend and Backend Elm code
- Caches dependencies for faster builds

The CI runs on every push to `main` and on all pull requests to ensure code quality and prevent regressions.

## License

This project is licensed under the Mozilla Public License 2.0 - see the [LICENSE](LICENSE) file for details.
