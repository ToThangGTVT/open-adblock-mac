#!/usr/bin/env bash
# Builds the Rust core (git submodule open-adblock-core, branch main) into the xcframework the
# OpenAdBlockCore Swift package links. Run after cloning and whenever the submodule changes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -f open-adblock-core/Cargo.toml ]] || git submodule update --init open-adblock-core
MACOSX_DEPLOYMENT_TARGET=14.0 bash open-adblock-core/scripts/build-apple.sh
