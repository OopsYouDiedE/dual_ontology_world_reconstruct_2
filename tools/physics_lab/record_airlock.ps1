param(
    [string]$Out = '.runtime/physics-lab/l03/relay-final',
    [string]$Godot = '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '../..')
try {
    New-Item -ItemType Directory -Force $Out | Out-Null
    $Dest = (Resolve-Path -LiteralPath $Out).Path
    $Raw = Join-Path $Dest 'playthrough-source.avi'
    $MP4 = Join-Path $Dest 'L03-Observer-Airlock.mp4'
    $Log = Join-Path $Dest 'movie.log'
    & $Godot --path . --rendering-method forward_plus --resolution 1280x720 --disable-vsync `
        --fixed-fps 30 --write-movie $Raw --log-file $Log `
        res://scenes/physics_lab/airlock/Airlock.tscn -- --airlock-film
    if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath $Log -SimpleMatch 'OBSERVER_AIRLOCK_CLEAR' -Quiet)) {
        throw "The recorded run did not clear L03. See $Log"
    }
    & ffmpeg -hide_banner -loglevel error -y -i $Raw -c:v libx264 -preset medium -crf 18 `
        -pix_fmt yuv420p -c:a aac -b:a 160k -movflags +faststart $MP4
    if ($LASTEXITCODE -ne 0) { throw 'FFmpeg could not encode the recorded run.' }
    Write-Output $MP4
}
finally { Pop-Location }
