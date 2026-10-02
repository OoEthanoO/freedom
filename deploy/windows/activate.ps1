[CmdletBinding()]
param([string]$Root = 'C:\ProgramData\Freedom', [switch]$Rollback)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-Administrator
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$lock = [IO.File]::Open((Join-Path $Root 'deploy.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    $config = Read-Json (Join-Path $Root 'server.json')
    if (-not $config) { throw 'Run install.ps1 first.' }
    $old = Read-Json (Join-Path $Root 'active.json')
    if ($old) { $null = Assert-Release $Root $old }
    $targetFile = if ($Rollback) { 'previous.json' } else { 'prepared.json' }
    $target = Read-Json (Join-Path $Root $targetFile)
    if (-not $target) { throw 'No saved release to activate.' }
    $null = Assert-Release $Root $target
    if ($Rollback) {
        # Otherwise the next poll would immediately re-deploy origin/main.
        $poller = Get-ScheduledTask -TaskName 'freedom-deploy' -ErrorAction SilentlyContinue
        if ($poller) {
            $launcher = Join-Path $Root 'ops\tick.ps1'
            if (@($poller.Actions | Where-Object { $_.Arguments -and $_.Arguments.Contains('"' + $launcher + '"') }).Count -ne 1) { throw 'Poller ownership does not match this runtime.' }
            Disable-ScheduledTask -TaskName 'freedom-deploy' | Out-Null
        }
    }
    if (-not (Test-Release $target 5)) {
        if (Get-NetTCPConnection -State Listen -LocalPort $target.port -ErrorAction SilentlyContinue) { throw 'Target port is occupied by an unexpected process.' }
        Register-WebTask $Root $target
    }
    if (-not (Test-Release $target)) { throw 'Saved release is unhealthy; traffic is unchanged.' }
    Set-ActiveRelease $Root $config $target $old
    Copy-Ops (Join-Path $target.release 'ops') (Join-Path $Root 'ops')
    if (-not $Rollback) {
        $prepared = Join-Path $Root 'prepared.json'
        if (Test-Path -LiteralPath $prepared) { Remove-Item -LiteralPath (Assert-UnderRoot $prepared $Root) -Force }
    }
    if ($old -and $old.taskName -ne $target.taskName) { Start-Sleep -Seconds 20; Stop-WebTask $Root $old }
    Write-Output ('Activated ' + $target.commit)
    if ($Rollback) { Write-Output 'Automatic deployment is disabled; re-run install.ps1 -EnableAutoDeploy to resume it.' }
} finally { $lock.Dispose() }
