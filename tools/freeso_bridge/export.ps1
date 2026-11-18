[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Snapshot,
    [Parameter(Mandatory)][string]$Output,
    [string]$ClientRoot
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if (!$ClientRoot) { $ClientRoot = Join-Path $root '.runtime/freeso/client' }
$client = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ClientRoot)
$required = @('FSO.SimAntics.dll', 'FSO.LotView.dll', 'Monogame/WindowsGL/MonoGame.Framework.dll')
$references = foreach ($file in $required) { Join-Path $client $file }
$missing = @($references | Where-Object { !(Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missing.Count) { throw "Missing upstream client assemblies (build the pinned FreeSO client first): $($missing -join ', ')" }
$receipt = Join-Path $client '.source-revision'
if (!(Test-Path -LiteralPath $receipt) -or (Get-Content -LiteralPath $receipt -Raw).Trim() -ne '4c6b3e8f5835b228723caea3c9f683c62f244f73') {
    throw "Expected the pinned client build receipt at $receipt."
}
$common = Join-Path $client 'FSO.Common.dll'
if (Test-Path -LiteralPath $common -PathType Leaf) { $references += $common }
$inputFile = (Resolve-Path -LiteralPath $Snapshot).Path
$outputFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
$csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (!(Test-Path -LiteralPath $csc -PathType Leaf)) { throw "Missing .NET Framework C# compiler: $csc" }
$build = Join-Path $root '.runtime/freeso_bridge'
New-Item -ItemType Directory -Force -Path $build | Out-Null
$exe = Join-Path $build 'FreeSOSnapshot.exe'
$refs = @($references | ForEach-Object { "/reference:$_" })
& $csc /nologo /target:exe "/out:$exe" /reference:System.Web.Extensions.dll @refs (Join-Path $PSScriptRoot 'Program.cs') (Join-Path $PSScriptRoot 'SnapshotBridge.cs')
if ($LASTEXITCODE -ne 0) { throw "Bridge compilation failed: $LASTEXITCODE" }
& $exe $client $inputFile $outputFile
if ($LASTEXITCODE -ne 0) { throw "Native snapshot export failed: $LASTEXITCODE" }
Write-Output $outputFile
