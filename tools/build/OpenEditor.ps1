param([switch]$ConfigureOnly)
$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$engineRoot = Join-Path $projectRoot ".runtime/godot/4.7.2"
$engine = Join-Path $engineRoot "Godot_v4.7.2-stable_mono_win64.exe"
if (!(Test-Path -LiteralPath $engine)) { throw "Project-local Godot .NET 4.7.2 is missing." }
# Self-contained settings do not change the user's other Godot installations.
$marker = Join-Path $engineRoot "_sc_"
if (!(Test-Path -LiteralPath $marker)) { New-Item -ItemType File $marker | Out-Null }
$settingsRoot = Join-Path $engineRoot "editor_data"
New-Item -ItemType Directory -Force $settingsRoot | Out-Null
$settingsPath = Join-Path $settingsRoot "editor_settings-4.7.tres"
if (!(Test-Path -LiteralPath $settingsPath)) {
    $settings = "[gd_resource type=`"EditorSettings`" format=3]`n`n[resource]`ndotnet/editor/external_editor = 4`n"
} else {
    $settings = Get-Content -LiteralPath $settingsPath -Raw
    if ($settings -match '(?m)^dotnet/editor/external_editor = .*$') {
        $settings = $settings -replace '(?m)^dotnet/editor/external_editor = .*$', 'dotnet/editor/external_editor = 4'
    } else { $settings += "`ndotnet/editor/external_editor = 4`n" }
}
Set-Content -LiteralPath $settingsPath -Value $settings -Encoding UTF8
if (!$ConfigureOnly) {
    Start-Process -FilePath $engine -ArgumentList @("--editor", "--path", ('"' + $projectRoot + '"')) -WorkingDirectory $projectRoot -WindowStyle Hidden
}
