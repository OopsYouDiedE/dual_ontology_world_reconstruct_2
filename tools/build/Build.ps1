param([ValidateSet("Debug", "ExportDebug", "ExportRelease")][string]$Configuration = "Debug")
$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
Push-Location $projectRoot
try {
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
    $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = "1"
    $env:DOTNET_CLI_HOME = Join-Path $projectRoot ".runtime/dotnet-home"
    $logRoot = Join-Path $projectRoot ".runtime/build-logs"
    New-Item -ItemType Directory -Force $logRoot | Out-Null
    $buildId = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $clock = [Diagnostics.Stopwatch]::StartNew()
    & dotnet build "DualOntologyWorldReconstruct2.csproj" --configuration $Configuration --nologo --verbosity minimal -maxcpucount -nodeReuse:true "-bl:$logRoot/$buildId.binlog" 2>&1 | Tee-Object -FilePath "$logRoot/$buildId.log"
    $buildExitCode = $LASTEXITCODE
    $clock.Stop()
    [ordered]@{ configuration = $Configuration; exit_code = $buildExitCode; elapsed_seconds = $clock.Elapsed.TotalSeconds; log = "$buildId.log"; binary_log = "$buildId.binlog" } | ConvertTo-Json | Set-Content "$logRoot/$buildId.json" -Encoding UTF8
    exit $buildExitCode
} finally { Pop-Location }
