# Accounting - Lamdera Elm Application

This is a full-stack web application for managing group expenses and accounting, built with Elm and Lamdera. It features user and group management, expense tracking with automatic debt calculation, data import/export functionality, and real-time synchronization.

**ALWAYS follow these instructions first and only use search or bash commands when the information here is incomplete or found to be in error.**

## Working Effectively

### Initial Setup and Dependencies
- **Check first**: Run `lamdera --version` to see if Lamdera is already installed before attempting any installation. Lamdera may be available via Nix or another package manager, not necessarily Node.js.
- If Lamdera is not available: Node.js 20 or later must be installed, then install Lamdera CLI globally: `npm install -g lamdera`
- Install Elm tooling: `npm install -g elm-format elm-review` (optional but recommended)
- **No additional build steps or package installation required** - Lamdera handles all Elm dependencies

### Core Build Commands
- **Compile Frontend**: `lamdera make src/Frontend.elm --output=/dev/null`
  - **Cold build time**: ~30 seconds (when elm-stuff doesn't exist)
  - **Warm build time**: <1 second (subsequent builds)
  - **NEVER CANCEL**: Set timeout to 60+ seconds for cold builds
- **Compile Backend**: `lamdera make src/Backend.elm --output=/dev/null`
  - **Build time**: <1 second (after Frontend is compiled first)
  - **NEVER CANCEL**: Set timeout to 60+ seconds for safety

### Development Server
- **Start development server**: `lamdera live`
  - **Cold startup time**: ~30-45 seconds (rebuilds dependencies)
  - **Warm startup time**: <5 seconds (with existing elm-stuff)
  - **NEVER CANCEL**: Set timeout to 120+ seconds for cold starts
  - **Server URL**: http://localhost:8000
  - **Server responds with HTTP 200** when fully operational
  - Press Ctrl+C to stop the server

### Code Formatting and Linting
- **Format code**: `elm-format src/ --yes`
  - **Time**: <1 second
  - **Validates formatting**: `elm-format --validate src/`
- **Lint code**: `elm-review` (from project root)
  - **Time**: <5 seconds when working
  - **Note**: May fail with network connectivity issues during dependency resolution
  - **Alternative**: Skip elm-review if network issues persist - the CI will catch linting issues

## Validation

### CRITICAL: Always Manually Test After Changes
After making any code changes, you **MUST** validate the application works by running through complete scenarios:

1. **Start the development server**: `lamdera live`
2. **Access the application**: Visit http://localhost:8000 in browser or test with `curl http://localhost:8000`
3. **Verify HTTP 200 response**: `curl -s -o /dev/null -w "%{http_code}" http://localhost:8000`
4. **Test core functionality** (if accessible):
   - User authentication flow
   - Group management features
   - Expense tracking functionality
   - Data import/export features

### Pre-commit Validation
Before completing any changes:
1. **Format code**: `elm-format src/ --yes`
2. **Compile both modules**: 
   - `lamdera make src/Frontend.elm --output=/dev/null`
   - `lamdera make src/Backend.elm --output=/dev/null`
3. **Test development server**: `lamdera live` and verify it serves correctly
4. **Manual testing**: Run through at least one end-to-end user scenario

## Project Structure

### Core Files
- `src/Frontend.elm` - Frontend Elm application
- `src/Backend.elm` - Backend Elm application  
- `src/Types.elm` - Shared type definitions
- `src/Env.elm` - Environment configuration
- `src/Evergreen/` - Lamdera type migration system (auto-generated)

### Configuration Files
- `elm.json` - Elm project configuration with Lamdera dependencies
- `review/` - elm-review configuration directory
- `.github/workflows/build.yml` - CI pipeline that compiles Frontend and Backend

### Key Dependencies
- **lamdera/core**: Full-stack Elm framework
- **mdgriffith/elm-ui**: UI framework
- **elm/time**, **justinmimbs/date**: Date/time handling
- **elm/regex**: Text processing
- **miniBill/elm-codec**: Data serialization

## Common Tasks

### Repository Root Structure
```
.
├── .github/workflows/    # CI/CD pipeline
├── elm.json             # Project dependencies
├── src/                 # Source code
│   ├── Frontend.elm     # Frontend application
│   ├── Backend.elm      # Backend application
│   ├── Types.elm        # Shared types
│   ├── Env.elm          # Environment config
│   └── Evergreen/       # Migration system
├── review/              # elm-review configuration
├── README.md            # Project documentation
└── LICENSE              # Mozilla Public License 2.0
```

### Lamdera-Specific Considerations
- **This is a Lamdera application** - do not try to build individual Elm files with `elm make`
- **Type migrations**: The `src/Evergreen/` directory contains auto-generated migration code for type changes. **Do NOT manually create or generate files in `src/Evergreen/`** - they are automatically generated by running `lamdera check`. If new migration files are needed and running locally, run `lamdera check --force` to have them generated (`--force` is required since plain `lamdera check` only works on the main branch), then modify the generated files to complete the migration logic. This command cannot be run in CI or non-local environments.
- **No separate frontend/backend servers** - Lamdera handles full-stack development in one process
- **Real-time sync** - Changes to shared types automatically trigger migrations
- **Production deployment** - Use Lamdera's hosting platform, not traditional web servers

### Troubleshooting
- **elm-stuff corruption**: Delete `elm-stuff/` directory and rebuild - adds ~30 seconds to next build
- **Network dependency issues**: May affect elm-review; CI will catch issues if local linting fails
- **Port conflicts**: Default port 8000; use `lamdera live --port=XXXX` to specify different port
- **Type migration errors**: Check `src/Evergreen/Migrate/` files if encountering type-related build failures

### CI Pipeline
The `.github/workflows/build.yml` automatically:
- Sets up Node.js 20
- Installs Lamdera globally
- Caches Lamdera dependencies
- Compiles both Frontend and Backend modules
- **Build time in CI**: ~1-2 minutes including setup

## Expected Command Outputs

### Successful Frontend Compilation
```
$ lamdera make src/Frontend.elm --output=/dev/null
Success!
```

### Successful Backend Compilation  
```
$ lamdera make src/Backend.elm --output=/dev/null
Success!
```

### Successful Development Server Start
```
$ lamdera live
Go to http://localhost:8000 to see your project dashboard.
Listening on http://0.0.0.0:8000
```

### Successful Code Formatting
```
$ elm-format src/ --yes
Processing file src/Frontend.elm
Processing file src/Backend.elm
...
(lists all processed .elm files)
```

Remember: **NEVER CANCEL long-running commands**. Builds may take 30+ seconds on cold start, development server may take 45+ seconds on first launch. Always set appropriate timeouts (60+ seconds for builds, 120+ seconds for server start).