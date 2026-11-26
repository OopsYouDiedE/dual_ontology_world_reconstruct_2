#!/bin/sh
# Quad-retopologise one hero's Tripo parts; QuadriFlow can crash Blender outright, so rerun until the script
# reports completion (the crashed part keeps its Tripo triangles). Usage: retopo_parts.sh <hero>
hero="$1"
for i in 1 2 3 4 5 6 7 8 9 10; do
  log=$(.runtime/cast-pass/blender.sh --python tools/cast/fit/retopo_parts.py -- --hero "$hero" 2>&1)
  echo "$log" | grep -E "^(PART|CRASHED_KEEP|RETOPO_PARTS_DONE)" | tail -3
  echo "$log" | grep -q "^RETOPO_PARTS_DONE" && exit 0
done
exit 1
