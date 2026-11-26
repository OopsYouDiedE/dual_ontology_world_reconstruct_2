#!/bin/sh
# Retopologise heroes one Blender process each; QuadriFlow sometimes crashes outright, so on a crash the
# next coarser voxel size is tried in a fresh process.  Usage: tools/cast/fit/retopo_all.sh [hero ...]
cd "$(dirname "$0")/../../.."
BLENDER="/c/Program Files/Blender Foundation/Blender 4.2/blender.exe"
for hero in ${@:-detective hale quer lucian}; do
  for voxel in 0.005 0.008 0.012; do
    "$BLENDER" -b --factory-startup --python tools/cast/fit/retopo.py -- --heroes "$hero" --voxel "$voxel" \
      > ".runtime/facefit/retopo-$hero.log" 2>&1
    if grep -q "^RETOPO $hero" ".runtime/facefit/retopo-$hero.log"; then
      grep "^RETOPO $hero" ".runtime/facefit/retopo-$hero.log"; break
    fi
    echo "RETOPO_CRASH $hero voxel $voxel"
  done
done
