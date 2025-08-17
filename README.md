# Accounting

A web application for managing group expenses and accounting, built with Elm and Lamdera.

## Features

- User and group management
- Expense tracking with automatic debt calculation
- Data import/export functionality
- Real-time synchronization using Lamdera

## Development

This project is built with [Elm](https://elm-lang.org/) and [Lamdera](https://lamdera.com/), a platform for building full-stack Elm applications.

### Prerequisites

- [Elm](https://guide.elm-lang.org/install/) 0.19.1
- [Lamdera](https://lamdera.com/) for local development

### Building

To build the project:

```bash
elm make src/Frontend.elm --output=dist/frontend.js
elm make src/Backend.elm --output=dist/backend.js
```

### Code Quality

This project uses [elm-review](https://package.elm-lang.org/packages/jfmengels/elm-review/latest/) for linting and code quality checks. The configuration is in the `review/` directory.

To run elm-review locally:

```bash
npx elm-review
```

## Continuous Integration

The project uses GitHub Actions for continuous integration. The workflow automatically:

- ✅ Compiles both Frontend and Backend Elm code
- ✅ Runs elm-review for code quality checks
- ✅ Caches dependencies for faster builds

The CI runs on every push to `main` and on all pull requests to ensure code quality and prevent regressions.

## License

This project is licensed under the Mozilla Public License 2.0 - see the [LICENSE](LICENSE) file for details.