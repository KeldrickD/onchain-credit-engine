#!/usr/bin/env bash
set -euo pipefail

# Prefer system forge if available; fall back to default Foundry install path.
if command -v forge >/dev/null 2>&1; then
  forge test -vvv
elif [ -x "$HOME/.foundry/bin/forge" ]; then
  "$HOME/.foundry/bin/forge" test -vvv
else
  echo "forge not found. Install Foundry: https://book.getfoundry.sh/getting-started/installation"
  exit 1
fi
