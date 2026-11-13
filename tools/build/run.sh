#!/usr/bin/env bash
# 构建后启动。用环境变量 GODOT_MONO 指向 Godot .NET (mono) 4.7.2 可执行文件。
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT_MONO:-$(command -v godot-mono || command -v Godot_v4.7.2-stable_mono_linux.x86_64 || true)}"
[ -x "${GODOT:-}" ] || { echo "请设置 GODOT_MONO=/path/to/Godot_v4.7.2-stable_mono_*"; exit 2; }
tools/build/build.sh
exec "$GODOT" --path . "$@"
