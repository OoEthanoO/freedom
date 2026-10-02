[CmdletBinding()]
param([string]$Root = 'C:\ProgramData\Freedom')
. (Join-Path $PSScriptRoot 'common.ps1')
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$log = Join-Path $Root 'logs\poller.log'
try {
    if (-not (Read-Json (Join-Path $Root 'active.json'))) { throw 'No active release; automatic deployment is not enabled yet.' }
    if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 5MB) {
        $null = Assert-UnderRoot $log $Root
        Move-Item -LiteralPath $log -Destination ($log + '.previous') -Force
    }
    & (Join-Path $Root 'ops\deploy.ps1') -Root $Root >> $log 2>&1
} catch {
    Add-Content -LiteralPath $log -Value ((Get-Date).ToString('o') + ' ' + $_.Exception.Message)
    exit 1
}
