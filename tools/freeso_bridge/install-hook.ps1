[CmdletBinding()]
param([Parameter(Mandatory)][string]$UpstreamWorktree)
$ErrorActionPreference = 'Stop'
$runtime = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../.runtime')).Path
$worktree = (Resolve-Path -LiteralPath $UpstreamWorktree).Path
if (!(Test-Path -LiteralPath $worktree -PathType Container) -or
    !$worktree.StartsWith($runtime + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Patch only a disposable upstream copy below the project .runtime directory.'
}
$client = Join-Path $worktree 'TSOClient/tso.client'
$screen = Join-Path $client 'UI/Screens/SandboxGameScreen.cs'
$project = Join-Path $client 'FSO.Client.csproj'
$queue = Join-Path $worktree 'TSOClient/tso.simantics/Engine/VMQueuedAction.cs'
$selector = Join-Path $worktree 'TSOClient/tso.simantics/Primitives/VMFindBestAction.cs'
foreach ($path in @($screen, $project, $queue, $selector)) {
    $item = Get-Item -LiteralPath $path
    while ($item -and $item.FullName.StartsWith($runtime, [StringComparison]::OrdinalIgnoreCase)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing linked patch path: $($item.FullName)" }
        $item = if ($item -is [IO.FileInfo]) { $item.Directory } else { $item.Parent }
    }
}

$screenText = [IO.File]::ReadAllText($screen)
$projectText = [IO.File]::ReadAllText($project)
$screenHook = @"
            if (vm != null)
            {
                var bridgeVm = vm;
                var bridgeTick = global::DuelView.FreeSOBridge.LiveTickHook.BeforeUpdate(bridgeVm);
                bridgeVm.Update();
                global::DuelView.FreeSOBridge.LiveTickHook.AfterUpdate(bridgeVm, bridgeTick);
            }
"@
$screenAnchor = '            if (vm != null) vm.Update();'
$compileAnchor = '    <Compile Include="UI\Screens\SandboxGameScreen.cs" />'
$projectHook = @"
    <Compile Include="UI\Screens\SandboxGameScreen.cs" />
    <Compile Include="DuelView.LiveTickHook.cs" />
    <Compile Include="DuelView.SnapshotBridge.cs" />
"@
$referenceAnchor = '    <Reference Include="System" />'
$referenceHook = @"
    <Reference Include="System" />
    <Reference Include="System.Web.Extensions" />
"@
function Add-Hook([string]$Text, [string]$Anchor, [string]$Hook, [string]$Marker, [string]$Path) {
    $newLine = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $replacement = $Hook.TrimEnd("`r", "`n") -replace '\r?\n', $newLine
    if ($Text.Contains($replacement)) { return $Text }
    if ($Text.Contains($Marker) -or [regex]::Matches($Text, [regex]::Escape($Anchor)).Count -ne 1) {
        throw "Pinned upstream hook anchor changed or patch is incomplete: $Path"
    }
    return $Text.Replace($Anchor, $replacement)
}
$screenText = Add-Hook $screenText $screenAnchor $screenHook 'DuelView.FreeSOBridge' $screen
$projectText = Add-Hook $projectText $compileAnchor $projectHook 'DuelView.LiveTickHook.cs' $project
$projectText = Add-Hook $projectText $referenceAnchor $referenceHook 'System.Web.Extensions' $project
$queueText = [IO.File]::ReadAllText($queue)
$selectorText = [IO.File]::ReadAllText($selector)
$queueAnchor = '        public short Priority = (short)VMQueuePriority.Idle;'
$queueHook = @"
        public short Priority = (short)VMQueuePriority.Idle;
        // Process-local provenance; intentionally excluded from VM save/restore and net state.
        public bool DuelViewSelectedByFindBestAction;
"@
$selectAnchor = '                context.Caller.Thread.EnqueueAction(qaction);'
$selectHook = @"
                context.Caller.Thread.EnqueueAction(qaction);
                qaction.DuelViewSelectedByFindBestAction = true;
"@
$queueText = Add-Hook $queueText $queueAnchor $queueHook 'DuelViewSelectedByFindBestAction' $queue
$selectorText = Add-Hook $selectorText $selectAnchor $selectHook 'DuelViewSelectedByFindBestAction' $selector
foreach ($name in @('LiveTickHook.cs', 'SnapshotBridge.cs')) {
    $destination = Join-Path $client "DuelView.$name"
    if ((Test-Path -LiteralPath $destination) -and ((Get-Item -LiteralPath $destination).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing linked bridge source: $destination"
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $destination -Force
}
[IO.File]::WriteAllText($screen, $screenText)
[IO.File]::WriteAllText($project, $projectText)
[IO.File]::WriteAllText($queue, $queueText)
[IO.File]::WriteAllText($selector, $selectorText)
Write-Output 'Installed DuelView live sandbox VM hook in the disposable FreeSO source copy.'
