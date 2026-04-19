#!/usr/bin/env bash
set -euo pipefail

echo "[devcontainer] Node version: $(node --version)"

if command -v lamdera >/dev/null 2>&1; then
  echo "[devcontainer] Lamdera already installed: $(lamdera --version)"
else
  echo "[devcontainer] Installing Lamdera CLI..."
  npm install -g lamdera
fi

echo "[devcontainer] Installing Elm tooling and Squad CLI..."
npm install -g elm-format elm-review @bradygaster/squad-cli

if command -v gh >/dev/null 2>&1; then
  if gh extension list 2>/dev/null | grep -q "github/gh-copilot"; then
    echo "[devcontainer] gh-copilot extension already installed."
  else
    echo "[devcontainer] Installing gh-copilot extension..."
    gh extension install github/gh-copilot || true
  fi
fi

echo "[devcontainer] Setup complete."