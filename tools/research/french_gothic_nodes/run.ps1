param([Parameter(Mandatory)][string]$Blender)
$ErrorActionPreference='Stop'
$root=(Resolve-Path "$PSScriptRoot/../../..").Path
$out=Join-Path $root '.runtime/french-gn'
New-Item -ItemType Directory -Force $out | Out-Null
$revision='b49b3c1dca15a57f3696e23c6f3ba8badf1fa6a3'
$base="https://raw.githubusercontent.com/IRCSS/Blender-Geometry-Node-French-Houses/$revision"
$files=@{
 'GeometryNodesFrenchHous.blend'=@('main','F44B4BE96176204ADA3FD768327E2A86129F536C6412129ECA0478C72B3D5AE5');
 'Demo-MagicSchoolV2.blend'=@('demo','0E755628AFB55865358FA3D1020A1ACD64B7D262B780BA7FD52EF828C923C3B9')
}
foreach($name in $files.Keys){
 $path=Join-Path $out $name
 if(!(Test-Path $path)){Invoke-WebRequest "$base/$name" -OutFile $path}
 if((Get-FileHash $path).Hash -ne $files[$name][1]){throw "SHA-256 mismatch: $path"}
 $target=Join-Path $out $files[$name][0]
 & $Blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python "$PSScriptRoot/extract.py" -- extract $target $path
 if($LASTEXITCODE -ne 0){throw "Blender extraction failed: $path"}
 Copy-Item "$PSScriptRoot/LICENSE.upstream" "$target/LICENSE.txt" -Force
}
