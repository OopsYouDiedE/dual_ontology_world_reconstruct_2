#!/bin/sh
# Build one hero from its Tripo parts: first run measures the skeleton stature that puts the crown at the
# designed height, second run builds with it. Usage: build_tripo_parts.sh <hero> <UAL glb> [out dir]
set -e
hero="$1"; motion="$2"; out="${3:-assets/characters/heroes}"
W() { cygpath -w "$1"; }
run() { .runtime/cast-pass/blender.sh --python tools/cast/fit/build_tripo_parts.py -- --motion "$(W "$motion")" --hero "$hero" --out "$(W "$out")" "$@"; }
log=$(run 2>&1) || { echo "$log" | tail -40; exit 1; }
s=$(echo "$log" | sed -n "s/^RESTATURE $hero \([0-9.]*\).*/\1/p")
if [ -n "$s" ]; then log=$(run --stature "$s" 2>&1) || { echo "$log" | tail -40; exit 1; }; fi
echo "$log" | grep -E "^(RESTATURE|PAINT|PARTS_PASS)" || true
