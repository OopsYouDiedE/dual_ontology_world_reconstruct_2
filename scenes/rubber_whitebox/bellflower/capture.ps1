param(
    [int]$Seed = 1,
    [switch]$Strong,
    [string]$Godot = '',
    [string]$Python = '',
    [string]$Output = 'res://.runtime/bellflower/review'
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
if (!$Godot) { $Godot = Join-Path $root '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe' }
if (!$Python) { $Python = (Get-Command python -ErrorAction Stop).Source }
$opts = @("--python=$Python", "--seed=$Seed", "--capture=$Output")
if ($Strong) { $opts += '--strong' }
& $Godot --path $root --rendering-method forward_plus --resolution 1600x1000 res://scenes/rubber_whitebox/bellflower/Bellflower.tscn -- @opts
exit $LASTEXITCODE
