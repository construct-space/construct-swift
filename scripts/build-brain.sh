#!/bin/bash
# Builds the Go "brain" operator binary into the app resources as a sidecar.
# The binary is gitignored (large, built artifact) — run this before building.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRAIN_SRC="${BRAIN_SRC:-$DIR/../construct-app/brain}"
OUT="$DIR/App/Construct/Resources/sidecars"
mkdir -p "$OUT"
echo "Building brain from $BRAIN_SRC → $OUT/construct-brain"
( cd "$BRAIN_SRC" && GOOS=darwin GOARCH=arm64 go build -o "$OUT/construct-brain" . )
chmod +x "$OUT/construct-brain"
echo "Done: $(ls -la "$OUT/construct-brain" | awk '{print $5}') bytes"
