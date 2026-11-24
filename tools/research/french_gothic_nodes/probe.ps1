param([Parameter(Mandatory)][string]$Blender,[Parameter(Mandatory)][string]$LibraryDir)
$ErrorActionPreference='Stop'
$out=(Resolve-Path $LibraryDir).Path
$cases=@(
 @('ChurchA-Front'),@('GenerateChurchBuildingB'),@('ChurchFrontTowers'),@('DomaTower'),
 @('Generate Gothic Square Tower'),@('Generate Gothic Square Tower','Height','12.0'),
 @('WindowFromEdges'),@('ArcsFromEdges'),@('Gothic SupportColumn From EDge'),@('GenerateStairCase'),
 @('Generate Cathedral Combined')
)
$results=@()
foreach($case in $cases){
 $a=@($case);$log=Join-Path $out (($a -join '_')+'.log')
 & $Blender -b --factory-startup --disable-autoexec --python-exit-code 1 --python "$PSScriptRoot/extract.py" -- probe $out @a *> $log
 if($LASTEXITCODE -ne 0){throw "Probe failed; inspect $log"}
 $line=Get-Content $log | Where-Object {$_ -match '^PROBE_JSON '} | Select-Object -Last 1
 if(!$line){throw "Missing probe result: $log"}
 $results+=($line.Substring(11) | ConvertFrom-Json)
}
$results | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out 'probes.json') -Encoding utf8
