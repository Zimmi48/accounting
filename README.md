# Accounting

A web application for managing group expenses and accounting, built with Elm and Lamdera.

## Features

- User and group management
- Expense tracking with automatic debt calculation
- Data import/export functionality
- Real-time synchronization using Lamdera

## Development

This project is built [Lamdera](https://lamdera.com/), a platform for building full-stack [Elm](https://elm-lang.org/) applications.

### Prerequisites

- [Lamdera](https://lamdera.com/)
- elm-format to keep the code properly formatted at each commit

### Building

To build and test the project locally:

```bash
lamdera live
```

## Continuous Integration

The project uses GitHub Actions for continuous integration. The workflow automatically:

- Compiles both Frontend and Backend Elm code
- Caches dependencies for faster builds

The CI runs on every push to `main` and on all pull requests to ensure code quality and prevent regressions.

## License

This project is licensed under the Mozilla Public License 2.0 - see the [LICENSE](LICENSE) file for details.