#!/usr/bin/env bash
# Installs the repository's git pre-commit hooks into .git/hooks/.
# Run once after cloning: bash tools/install-hooks.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_SRC="$REPO_ROOT/tools/hooks"
HOOKS_DST="$REPO_ROOT/.git/hooks"

install_hook() {
  local name="$1"
  cp "$HOOKS_SRC/$name" "$HOOKS_DST/$name"
  chmod +x "$HOOKS_DST/$name"
  echo "  installed $name"
}

echo "Installing git hooks..."
install_hook pre-commit
echo "Done."
