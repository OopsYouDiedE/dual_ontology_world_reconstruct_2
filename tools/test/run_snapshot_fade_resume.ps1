param([string[]]$Cases = @('opening-free', 'opening-black', 'opening-fade', 'corridor-cover', 'corridor-reveal', 'corridor-out', 'transit-cover', 'transit-reveal', 'chapter-cover', 'chapter-reveal', 'identity'), [switch]$ResumeOnly, [string]$WorkId = 'snapshot-fade-resume-v1')
$ErrorActionPreference = 'Stop'
$projectRoot = 'C:\Users\iii\Desktop\dual_ontology_world_reconstruct_2'
$godotExe = Join-Path $projectRoot '.runtime\godot\4.7.2-standard\Godot_v4.7.2-stable_win64.exe'
$pythonExe = Join-Path $projectRoot '.runtime\python\Scripts\python.exe'
$reviewLogger = Join-Path $projectRoot '.runtime\log_review.py'
$resultDir = Join-Path $projectRoot '.runtime\fade-resume\final'
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
$launches = [System.Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath (Join-Path $resultDir 'launches-gpu.json')) {
    foreach ($previous in (Get-Content -LiteralPath (Join-Path $resultDir 'launches-gpu.json') -Raw | ConvertFrom-Json)) {
        if ($previous.case -notin $Cases -or ($ResumeOnly -and $previous.mode -eq 'prepare')) { $launches.Add($previous) }
    }
}

function Invoke-FadeCase([string]$caseName, [bool]$prepare) {
    $mode = if ($prepare) { 'prepare' } else { 'resume' }
    $stem = "$caseName-$mode-gpu"
    $reportPath = Join-Path $resultDir "$stem.json"
    $identityPath = Join-Path $resultDir "$stem-process.json"
    $fixturePath = if ($caseName -eq 'opening-free') {
        Join-Path $projectRoot '.runtime\checkpoints\fixtures\opening-free.json'
    } else { Join-Path $resultDir "$caseName-fixture.json" }
    $gameArgs = @('--path', $projectRoot, '--script', 'res://tools/test/snapshot_fade_resume.gd',
        '--rendering-method', 'gl_compatibility', '--resolution', '1440x900', '--',
        "--dv-fade-case=$caseName", "--dv-fade-output=$reportPath", '--dv-fade-capture=true',
        '--dv-checkpoint-auto=false', "--dv-checkpoint-output=$resultDir\shutdown-unused.json",
        '--dv-save-slot=snapshot-fade-development')
    if ($prepare) { $gameArgs += '--dv-fade-prepare=true' }
    elseif ($caseName -ne 'identity') { $gameArgs += "--dv-snapshot=$fixturePath" }
    $startedAt = Get-Date
    $process = Start-Process -FilePath $godotExe -ArgumentList $gameArgs -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $resultDir "$stem.stdout.log") -RedirectStandardError (Join-Path $resultDir "$stem.stderr.log")
    $osIdentity = Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)" | Select-Object ProcessId, ExecutablePath, CommandLine
    $osIdentity | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $identityPath -Encoding UTF8
    if ($null -eq $osIdentity -or $osIdentity.ExecutablePath -ne $godotExe -or -not $osIdentity.CommandLine.Contains("--path $projectRoot ")) {
        throw "Project/PID identity rejected for $stem"
    }
    if (-not $process.WaitForExit(15000)) {
        $process.Kill()
        throw "Timed out: $stem"
    }
    $process.Refresh()
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    $pidMatches = $report.source_identity.process_id -eq $process.Id
    $rootMatches = $report.source_identity.project_root.Replace('/', '\').TrimEnd('\') -eq $projectRoot
    $stderr = Get-Content -LiteralPath (Join-Path $resultDir "$stem.stderr.log") -Raw
    $entry = [ordered]@{case=$caseName; mode=$mode; pid=$process.Id; exit_code=$process.ExitCode; pass=$report.pass; checks=$report.checks.Count; elapsed_seconds=[Math]::Round(((Get-Date)-$startedAt).TotalSeconds, 2); pid_matches=$pidMatches; project_matches=$rootMatches; stderr_empty=[string]::IsNullOrWhiteSpace($stderr); os_identity=$osIdentity; report=$reportPath; fixture=$fixturePath}
    $launches.Add($entry)
    ConvertTo-Json -InputObject $launches.ToArray() -Depth 8 | Set-Content -LiteralPath (Join-Path $resultDir 'launches-gpu.json') -Encoding UTF8
    $resultText = "$stem : $($report.checks.Count) checks, pass=$($report.pass), PID=$($process.Id), exit=$($process.ExitCode), PID/project match=$pidMatches/$rootMatches; development snapshots, acceptance_eligible=false"
    & $pythonExe $reviewLogger check $WorkId "GPU snapshot fade $stem" $resultText --evidence $reportPath $identityPath (Join-Path $resultDir 'launches-gpu.json')
    if ($LASTEXITCODE -ne 0) { throw "Review recording failed: $stem" }
    if (-not $report.pass -or $process.ExitCode -ne 0 -or -not $pidMatches -or -not $rootMatches -or -not [string]::IsNullOrWhiteSpace($stderr)) { throw "Regression failed: $stem" }
    Write-Output $resultText
}

foreach ($caseName in $Cases) {
    if (-not $ResumeOnly -and $caseName -notin @('opening-free', 'identity')) { Invoke-FadeCase $caseName $true }
    Invoke-FadeCase $caseName $false
}
