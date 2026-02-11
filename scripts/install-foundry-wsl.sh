#!/bin/bash
# Run in WSL (Ubuntu): bash install-foundry-wsl.sh
# Verifies: forge --version && cast --version && anvil --version

set -e
echo "Installing Foundry..."
curl -L https://foundry.paradigm.xyz | bash

echo ""
echo "Sourcing ~/.bashrc and running foundryup..."
source "$HOME/.bashrc" 2>/dev/null || true
"$HOME/.foundry/bin/foundryup"

echo ""
echo "Verifying installation..."
"$HOME/.foundry/bin/forge" --version
"$HOME/.foundry/bin/cast" --version
"$HOME/.foundry/bin/anvil" --version

echo ""
echo "Run tests: cd contracts && forge test -vvv"
