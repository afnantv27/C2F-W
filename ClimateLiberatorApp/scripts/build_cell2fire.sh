#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CELL2FIRE_DIR="$REPO_ROOT/Cell2Fire"
if [[ ! -d "$CELL2FIRE_DIR" ]]; then
  echo "Cell2Fire directory not found at $CELL2FIRE_DIR" >&2
  exit 1
fi
cd "$CELL2FIRE_DIR"
CXX=${CXX:-/opt/homebrew/bin/g++-15}
echo "Using compiler -> $CXX"
if [[ ! -x "$CXX" ]]; then
  echo "gcc/g++-15 not found at $CXX" >&2
  exit 1
fi
make -f makefile.macos clean || true
CXX="$CXX" make -f makefile.macos -j$(sysctl -n hw.logicalcpu)
