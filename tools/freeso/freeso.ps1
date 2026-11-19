[CmdletBinding()]
param(
    [ValidateSet('Check','Build','Launch')][string]$Action = 'Check',
    [string]$AssetRoot,
    [string]$MSBuild,
    [string]$RoomId,
    [string]$BlueprintId,
    [string]$LotDirectory,
    [string]$NuGet
)
$ErrorActionPreference = 'Stop'
$pin = '4c6b3e8f5835b228723caea3c9f683c62f244f73'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$source = Join-Path $root 'vendor/FreeSO'
$runtime = Join-Path $root '.runtime/freeso'
$out = Join-Path $runtime 'client'
$hookReceipt = Join-Path $out '.snapshot-hook'
$blueprintReceipt = Join-Path $out '.academy-blueprint-hook'
$installer = Join-Path $root 'tools/freeso_bridge/install-hook.ps1'
$exe = Join-Path $out 'FreeSO.exe'
$solution = Join-Path $source 'TSOClient/FreeSO.sln'
$receipt = Join-Path $out '.source-revision'
$problems = [Collections.Generic.List[string]]::new()
$buildProblems = [Collections.Generic.List[string]]::new()
$launchProblems = [Collections.Generic.List[string]]::new()

function FullPath([string]$Path) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}
function Run([string]$File, [string[]]$Arguments) {
    & $File @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$File failed (exit $LASTEXITCODE)." }
}
function IsFile([string]$Path) { Test-Path -LiteralPath $Path -PathType Leaf }
function Export-TrackedTree([string]$Repo, [string]$Revision, [string]$Destination, [string]$Archive) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Run git @('-C', $Repo, 'archive', '--format=tar', "--output=$Archive", $Revision)
    Run tar.exe @('-xf', $Archive, '-C', $Destination)
}
function New-ClientStartInfo([string]$Executable, [string]$WorkingDirectory, [string]$SnapshotPath, [string]$BlueprintPath) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.WorkingDirectory = $WorkingDirectory
    $start.Arguments = '-ogl -tso w'
    $start.UseShellExecute = $false
    $start.EnvironmentVariables.Remove('FREESO_VM_SNAPSHOT_PATH')
    if ($SnapshotPath) {
        $start.EnvironmentVariables['FREESO_VM_SNAPSHOT_PATH'] = $SnapshotPath
    }
    $start.EnvironmentVariables.Remove('FREESO_ACADEMY_BLUEPRINT_PATH')
    if ($BlueprintPath) { $start.EnvironmentVariables['FREESO_ACADEMY_BLUEPRINT_PATH'] = $BlueprintPath }
    return $start
}
function IsSafeId([string]$Id) {
    $Id -cmatch '\A[A-Za-z0-9][A-Za-z0-9_-]{0,63}\z' -and $Id -notmatch '\A(?:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])\z'
}
function ClientProblems {
    foreach ($file in @('FreeSO.exe','FSO.Client.dll','FSO.SimAntics.dll','Monogame/WindowsGL/MonoGame.Framework.dll')) {
        if (!(IsFile (Join-Path $out $file))) { "Client output missing: $file" }
    }
    if (!(Test-Path -LiteralPath (Join-Path $out 'Content/OGL/Effects') -PathType Container)) { 'Client output missing: Content/OGL/Effects' }
}

$snapshotPath = $null
if ($PSBoundParameters.ContainsKey('RoomId')) {
    if (!(IsSafeId $RoomId)) {
        [Console]::Error.WriteLine('RoomId must be 1-64 ASCII letters, digits, hyphens or underscores, starting with a letter or digit and not a reserved Windows device name.')
        exit 1
    }
    if (!$LotDirectory) { $LotDirectory = Join-Path $runtime 'lots' }
    $snapshotPath = Join-Path (FullPath $LotDirectory) "$RoomId.json"
    if (!(IsFile $hookReceipt) -or (Get-Content -LiteralPath $hookReceipt -Raw).Trim() -ne $pin) {
        $launchProblems.Add('RoomId requires a client built with the live snapshot hook. Run Build first.')
    }
} elseif ($PSBoundParameters.ContainsKey('LotDirectory')) {
    [Console]::Error.WriteLine('LotDirectory requires RoomId.')
    exit 1
}
$blueprintPath = $null
if ($PSBoundParameters.ContainsKey('BlueprintId')) {
    if (!(IsSafeId $BlueprintId)) {
        [Console]::Error.WriteLine('BlueprintId must be a safe 1-64 character template ID, without extension.')
        exit 1
    }
    $blueprintPath = Join-Path $root "content/academy_lots/$BlueprintId.xml"
    if (!(IsFile $blueprintPath)) {
        $launchProblems.Add("Academy blueprint missing: $blueprintPath")
    } else {
        try {
            $xmlSettings = [Xml.XmlReaderSettings]::new()
            $xmlSettings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
            $reader = [Xml.XmlReader]::Create($blueprintPath, $xmlSettings)
            try {
                [void]$reader.MoveToContent()
                if ($reader.Name -cne 'house' -or $reader.NamespaceURI) { throw 'Expected unqualified FreeSO <house> root.' }
                while ($reader.Read()) {}
            } finally { $reader.Dispose() }
        } catch { $launchProblems.Add("Invalid academy blueprint: $blueprintPath ($($_.Exception.Message))") }
    }
    if (!(IsFile $blueprintReceipt) -or (Get-Content -LiteralPath $blueprintReceipt -Raw).Trim() -ne $pin) {
        $launchProblems.Add('BlueprintId requires a client built with the academy blueprint hook. Run Build first.')
    }
}
if (!(Get-Command tar.exe -CommandType Application -ErrorAction SilentlyContinue)) { $buildProblems.Add('Windows tar.exe is required to extract the isolated build tree.') }
if (!(IsFile $installer)) { $buildProblems.Add('FreeSO live hook installer is missing: tools/freeso_bridge/install-hook.ps1') }

if ($env:OS -ne 'Windows_NT') { $problems.Add('This entry point requires Windows.') }
if (!(IsFile $solution)) {
    $problems.Add('Pinned FreeSO source missing: git submodule update --init --recursive --depth 1 -- vendor/FreeSO')
} else {
    $head = & git -C $source rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $head -ne $pin) { $problems.Add("FreeSO checkout must be at $pin.") }
    $dirty = & git -C $source status --porcelain --untracked-files=no --ignore-submodules=none
    if ($LASTEXITCODE -ne 0 -or $dirty) { $problems.Add('FreeSO has tracked changes or a dependency at the wrong revision.') }
    $submodules = & git -C $source submodule status --recursive
    if ($LASTEXITCODE -ne 0 -or ($submodules -match '^[-+U]')) { $buildProblems.Add('Initialize all pinned upstream submodules recursively.') }
}
if (!$MSBuild -and ${env:ProgramFiles(x86)}) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (IsFile $vswhere) {
        $MSBuild = & $vswhere -version '[16.0,17.0)' -products '*' -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
        if (!$MSBuild) { $MSBuild = & $vswhere -latest -products '*' -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1 }
    }
}
if (!$NuGet) { $NuGet = (Get-Command nuget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
if (!$MSBuild -or !(IsFile $MSBuild)) { $buildProblems.Add('Visual Studio MSBuild.exe required (upstream CI uses VS 2019); pass -MSBuild.') }
if (!$NuGet -or !(IsFile $NuGet)) { $buildProblems.Add('NuGet CLI required for packages.config restore; pass -NuGet or install nuget.exe on PATH.') }

# Match the unmodified WindowsLocator order. No registry writes, data copies or junctions.
$located = FullPath (Join-Path $out '../The Sims Online/TSOClient')
if (!(IsFile (Join-Path $located 'tuning.dat'))) {
    $located = 'C:/Program Files/Maxis/The Sims Online/TSOClient'
    if ($env:OS -eq 'Windows_NT') {
        $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine','Registry32')
        try {
            $key = $hklm.OpenSubKey('SOFTWARE\Maxis\The Sims Online')
            if ($key) { try { $installed = $key.GetValue('InstallDir'); if ($installed) { $located = Join-Path $installed 'TSOClient' } } finally { $key.Dispose() } }
        } finally { $hklm.Dispose() }
    }
}
$located = FullPath $located
if ($AssetRoot -and (FullPath $AssetRoot).TrimEnd('\','/') -ne $located.TrimEnd('\','/')) {
    $launchProblems.Add("AssetRoot is an assertion, not an upstream flag. Configure WindowsLocator (portable sibling or EA install registry). Detected: $located")
}
foreach ($asset in @('tuning.dat','objectdata/objects/objiff.far')) {
    if (!(IsFile (Join-Path $located $asset))) { $launchProblems.Add("Original TSO asset missing: $located [$asset]; supply a complete authorized EA installation.") }
}
foreach ($problem in @(ClientProblems)) { $launchProblems.Add($problem) }
if (!(IsFile $receipt) -or (Get-Content -LiteralPath $receipt -Raw).Trim() -ne $pin) { $launchProblems.Add('No successful build receipt for the pinned client.') }

try {
    switch ($Action) {
        'Check' {
            $result = [ordered]@{revision=$pin; assetRoot=$located; snapshotPath=$snapshotPath; blueprintPath=$blueprintPath; buildReady=($problems.Count + $buildProblems.Count -eq 0); launchReady=($problems.Count + $launchProblems.Count -eq 0); sourceIssues=@($problems.ToArray()); buildIssues=@($buildProblems.ToArray()); launchIssues=@($launchProblems.ToArray())}
            $result | ConvertTo-Json -Compress
            if (!$result.launchReady) { exit 2 }
        }
        'Build' {
            if ($problems.Count + $buildProblems.Count) { throw (($problems.ToArray() + $buildProblems.ToArray()) -join "`n") }
            $MSBuild = FullPath $MSBuild
            $NuGet = FullPath $NuGet
            $stage = Join-Path $runtime ('build-' + [Guid]::NewGuid().ToString('N'))
            $tree = Join-Path $stage 'src'
            $archive = Join-Path $stage 'source.tar'
            try {
                Export-TrackedTree $source $pin $tree $archive
                foreach ($line in $submodules) {
                    if ($line -notmatch '^ ([0-9a-f]{40}) (.+?)(?: \(.+\))?$') { throw "Unexpected submodule status: $line" }
                    $depRevision = $Matches[1]
                    $depPath = $Matches[2]
                    Export-TrackedTree (Join-Path $source $depPath) $depRevision (Join-Path $tree $depPath) $archive
                }
                & $installer -UpstreamWorktree $tree | Out-Host
                New-Item -ItemType Directory -Force -Path $out | Out-Null
                foreach ($marker in @($receipt,$hookReceipt,$blueprintReceipt)) { if (IsFile $marker) { Remove-Item -LiteralPath $marker } }
                $buildSolution = Join-Path $tree 'TSOClient/FreeSO.sln'
                Push-Location (Join-Path $tree 'Other/libs/FSOMonoGame')
                try { Run (Join-Path (Get-Location).Path 'protobuild.exe') @('--generate') } finally { Pop-Location }
                Run $NuGet @('restore',$buildSolution,'-NonInteractive')
                Run $MSBuild @($buildSolution,'/restore','/t:FSO_IDE','/p:Configuration=Release','/p:Platform=Any CPU',"/p:OutDir=$out/",'/nologo')
                $missing = @(ClientProblems)
                if ($missing.Count) { throw ($missing -join "`n") }
                Set-Content -LiteralPath $blueprintReceipt -Value $pin -Encoding Ascii
                Set-Content -LiteralPath $hookReceipt -Value $pin -Encoding Ascii
                Set-Content -LiteralPath $receipt -Value $pin -Encoding Ascii
            } finally {
                if (Test-Path -LiteralPath $stage -PathType Container) {
                    $resolvedStage = (Resolve-Path -LiteralPath $stage).Path
                    $resolvedRuntime = (Resolve-Path -LiteralPath $runtime).Path
                    if ((Split-Path $resolvedStage -Parent) -ne $resolvedRuntime -or (Split-Path $resolvedStage -Leaf) -cnotmatch '^build-[0-9a-f]{32}$' -or (Get-Item -LiteralPath $resolvedStage -Force).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
                        throw "Refusing to remove unexpected build staging path: $resolvedStage"
                    }
                    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
                }
            }
        }
        'Launch' {
            if ($problems.Count + $launchProblems.Count) { throw (($problems.ToArray() + $launchProblems.ToArray()) -join "`n") }
            if ($snapshotPath) { [IO.Directory]::CreateDirectory((Split-Path $snapshotPath -Parent)) | Out-Null }
            $start = New-ClientStartInfo $exe $out $snapshotPath $blueprintPath
            $process = [Diagnostics.Process]::Start($start)
            try {
                [ordered]@{pid=$process.Id; revision=$pin; executable=$exe; snapshotPath=$snapshotPath; blueprintPath=$blueprintPath} | ConvertTo-Json -Compress
            } finally { $process.Dispose() }
        }
    }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
