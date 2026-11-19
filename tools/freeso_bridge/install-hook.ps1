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
$loading = Join-Path $client 'UI/Screens/LoadingScreen.cs'
$cas = Join-Path $client 'UI/Screens/PersonSelectionEdit.cs'
$project = Join-Path $client 'FSO.Client.csproj'
$queue = Join-Path $worktree 'TSOClient/tso.simantics/Engine/VMQueuedAction.cs'
$selector = Join-Path $worktree 'TSOClient/tso.simantics/Primitives/VMFindBestAction.cs'
foreach ($path in @($screen, $loading, $cas, $project, $queue, $selector)) {
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
$loadingText = [IO.File]::ReadAllText($loading)
$loginCall = 'FSOFacade.Controller.ShowLogin();'
$startupCall = 'DuelViewEnterStartupScreen();'
$startupAnchor = '        private void AnimateLabel(string previousLabel, string newLabel)'
$startupHook = @'
        private static bool DuelViewBlueprintOpened;

        private void DuelViewEnterStartupScreen()
        {
            var academyPath = System.Environment.GetEnvironmentVariable("FREESO_ACADEMY_BLUEPRINT_PATH");
            if (!DuelViewBlueprintOpened && !string.IsNullOrEmpty(academyPath))
            {
                DuelViewBlueprintOpened = true;
                if (GlobalSettings.Default.DebugBody == 0) FSOFacade.Controller.ShowPersonCreation(null);
                else FSOFacade.Controller.EnterSandboxMode(academyPath, false);
            }
            else FSOFacade.Controller.ShowLogin();
        }

        private void AnimateLabel(string previousLabel, string newLabel)
'@
$startupCount = [regex]::Matches($loadingText, [regex]::Escape($startupCall)).Count
if ($startupCount -eq 0 -and !$loadingText.Contains('DuelViewBlueprintOpened')) {
    if ([regex]::Matches($loadingText, [regex]::Escape($loginCall)).Count -ne 2) {
        throw "Pinned FreeSO preload transitions changed: $loading"
    }
    $loadingText = $loadingText.Replace($loginCall, $startupCall)
} elseif ($startupCount -ne 2 -or !$loadingText.Contains('DuelViewBlueprintOpened')) {
    throw "Academy startup hook is incomplete: $loading"
}
$loadingText = Add-Hook $loadingText $startupAnchor $startupHook 'DuelViewBlueprintOpened' $loading

$cacheAnchor = '                using (var file = new BinaryReader(File.OpenRead(Path.Combine(FSOEnvironment.UserDir, "LocalHouse/") + filename.Substring(0, filename.Length - 4) + ".fsov")))'
$cacheHook = @'
                // Use the supplied native XML even if a local save shares its filename.
                if (DuelViewIsAcademyBlueprint(path)) throw new FileNotFoundException();
                using (var file = new BinaryReader(File.OpenRead(Path.Combine(FSOEnvironment.UserDir, "LocalHouse/") + filename.Substring(0, filename.Length - 4) + ".fsov")))
'@
$jobAnchor = "                        jobLevel = short.Parse(path.Substring(path.IndexOf('0'), 2));"
$jobHook = '                        if (DuelViewIsAcademyBlueprint(path)) jobLevel = -1;' + [Environment]::NewLine + '                        else ' + $jobAnchor.TrimStart()
$resetAnchor = '        public void BlueprintReset(string path)'
$resetHook = @'
        private static bool DuelViewIsAcademyBlueprint(string path)
        {
            var academyPath = Environment.GetEnvironmentVariable("FREESO_ACADEMY_BLUEPRINT_PATH");
            return !string.IsNullOrEmpty(academyPath) && Path.IsPathRooted(path)
                && string.Equals(Path.GetFullPath(path), academyPath, StringComparison.OrdinalIgnoreCase);
        }

        public void BlueprintReset(string path)
'@
$screenText = Add-Hook $screenText $cacheAnchor $cacheHook 'if (DuelViewIsAcademyBlueprint(path)) throw' $screen
$screenText = Add-Hook $screenText $jobAnchor $jobHook 'if (DuelViewIsAcademyBlueprint(path)) jobLevel' $screen
$screenText = Add-Hook $screenText $resetAnchor $resetHook 'private static bool DuelViewIsAcademyBlueprint' $screen

$casText = [IO.File]::ReadAllText($cas)
$casAnchor = '                GlobalShowDialog(new UISandboxSelector(), true);'
$casHook = @'
                var academyPath = System.Environment.GetEnvironmentVariable("FREESO_ACADEMY_BLUEPRINT_PATH");
                if (!string.IsNullOrEmpty(academyPath)) FSOFacade.Controller.EnterSandboxMode(academyPath, false);
                else GlobalShowDialog(new UISandboxSelector(), true);
'@
$casText = Add-Hook $casText $casAnchor $casHook 'FREESO_ACADEMY_BLUEPRINT_PATH' $cas

[IO.File]::WriteAllText($cas, $casText)
[IO.File]::WriteAllText($loading, $loadingText)
[IO.File]::WriteAllText($screen, $screenText)
[IO.File]::WriteAllText($project, $projectText)
[IO.File]::WriteAllText($queue, $queueText)
[IO.File]::WriteAllText($selector, $selectorText)
Write-Output 'Installed DuelView live sandbox VM hook in the disposable FreeSO source copy.'
