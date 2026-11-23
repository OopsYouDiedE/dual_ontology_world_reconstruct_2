# Input is a JSON array of absolute paths on stdin. Parse source; never execute it.
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$result = @{}
foreach ($path in (ConvertFrom-Json ([Console]::In.ReadToEnd()))) {
    $tokens = $errorsFound = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errorsFound)
    $result[$path] = @{
        issues = @($errorsFound | ForEach-Object { "PowerShell L$($_.Extent.StartLineNumber): $($_.Message)" })
        symbols = @($tree.FindAll({param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
            $n -is [System.Management.Automation.Language.TypeDefinitionAst] -or
            $n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]
        }, $true) | ForEach-Object {
            $n = $_
            $kind = if ($n -is [System.Management.Automation.Language.TypeDefinitionAst]) {'class'}
                elseif ($n.Parent -is [System.Management.Automation.Language.FunctionMemberAst]) {'method'}
                elseif ($n.IsFilter) {'filter'} elseif ($n.Name) {'function'} else {'script block'}
            $name = if ($n.Name) {$n.Name} else {'<script block>'}
            $params = if ($n.Parameters) {$n.Parameters} elseif ($n.Body.ParamBlock) {$n.Body.ParamBlock.Parameters}
            $sig = if ($null -ne $params) {'(' + (($params | ForEach-Object { $_.Extent.Text }) -join ', ') + ')'} else {''}
            ,@($name, $kind, $n.Extent.StartLineNumber, $n.Extent.EndLineNumber, $sig, $n.Extent.StartColumnNumber, $n.Extent.EndColumnNumber)
        })
    }
}
ConvertTo-Json -InputObject $result -Depth 8 -Compress
