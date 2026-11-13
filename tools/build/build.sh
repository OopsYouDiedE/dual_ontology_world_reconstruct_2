#!/usr/bin/env bash
# 跨平台构建（Linux / macOS / WSL）。Windows 继续用 Build.ps1。
set -euo pipefail
cd "$(dirname "$0")/../.."
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
command -v dotnet >/dev/null || { echo "未找到 dotnet，请安装 .NET SDK 8.0.x"; exit 2; }
dotnet build DualOntologyWorldReconstruct2.sln --configuration "${1:-Debug}" --verbosity minimal
