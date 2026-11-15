# Mixamo retarget cache

`prebake_mixamo_retarget_cache.gd` builds the target model's cached `AnimationLibrary` snapshot without rendering. Normal gameplay also builds the cache on a miss and uses it on later processes.

The default location is `user://mixamo-retarget-cache-v2`. Every entry has an immutable binary animation snapshot and a JSON manifest. The key includes the target skeleton, target model, source rig and animation inputs, retarget scripts, and retarget parameters. A missing, stale, corrupt, or incomplete entry is removed and rebuilt.

For a disposable headless validation cache, add `--animation-retarget-cache-dir=res://.runtime/animation-cache-checks/<run>/cache`. Add `--animation-retarget-cache-disable=1` to measure the direct retarget build.
