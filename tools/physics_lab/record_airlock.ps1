param(
    [string]$Out = '.runtime/physics-lab/l03/final-witness',
    [ValidateSet('clear','alternate','blocked','public','recoil','early','late','panic','death','solo')][string]$Case = 'clear',
    [string]$Godot = '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '../..')
try {
    New-Item -ItemType Directory -Force $Out | Out-Null
    $Dest = (Resolve-Path -LiteralPath $Out).Path
    $Raw = Join-Path $Dest "$Case-source.avi"
    $Name = if ($Case -eq 'clear') { 'L03-Blind-Relay.mp4' } else { "L03-$Case.mp4" }
    $MP4 = Join-Path $Dest $Name
    $Log = Join-Path $Dest "$Case-movie.log"
    & $Godot --path . --rendering-method forward_plus --resolution 1280x720 --disable-vsync `
        --fixed-fps 30 --write-movie $Raw --log-file $Log `
        res://scenes/physics_lab/airlock/Airlock.tscn -- --airlock-film "--airlock-case=$Case"
    if ($LASTEXITCODE -ne 0) { throw "Godot failed to record L03. See $Log" }
    $Prefix = 'OBSERVER_AIRLOCK_RESULT '
    $Receipt = Select-String -LiteralPath $Log -SimpleMatch $Prefix | Select-Object -Last 1
    if (-not $Receipt) { throw "Missing L03 result. See $Log" }
    $State = $Receipt.Line.Substring($Receipt.Line.IndexOf($Prefix) + $Prefix.Length) | ConvertFrom-Json
    $Expected = switch ($Case) {
        'clear' { $State.cleared -and -not $State.failed }
        'early' { $State.failed -eq 'DOUBLE_GAZE' -and $State.red[1] -gt 40 }
        'late' { $State.failed -eq 'FALL' }
        'panic' { $State.cleared -and -not $State.distorted -and $State.events.kind -contains 'GROUNDED' }
        default { $State.cleared -and -not $State.failed }
        'death' { $State.failed -eq 'DOUBLE_GAZE' -and $State.red[1] -gt 40 }
    }
    if (-not $Expected) { throw "Unexpected result for $Case. See $Log" }
    & ffmpeg -hide_banner -loglevel error -y -i $Raw -c:v libx264 -preset medium -crf 18 `
        -pix_fmt yuv420p -c:a aac -b:a 160k -movflags +faststart $MP4
    if ($LASTEXITCODE -ne 0) { throw 'FFmpeg could not encode the recorded run.' }
    Write-Output $MP4
}
finally { Pop-Location }
