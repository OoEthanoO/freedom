[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Release,
    [Parameter(Mandatory)][ValidateSet(3400,3401)][int]$Port,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$Commit)
. (Join-Path $PSScriptRoot 'common.ps1')
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$Release = Assert-UnderRoot $Release (Join-Path $Root 'releases')
$state = Read-Json (Join-Path $Release 'release.json')
$null = Assert-Release $Root $state
if ($state.release -ne $Release -or $state.commit -ne $Commit -or $state.port -ne $Port) { throw 'Launcher arguments do not match the saved release.' }
$config = Read-Json (Join-Path $Root 'server.json')
if (-not $config) { throw 'Runtime configuration is missing.' }
$env:NODE_ENV = 'production'; $env:NEXT_TELEMETRY_DISABLED = '1'
$env:TZ = 'America/Toronto'
$env:PORT = [string]$Port; $env:HOSTNAME = '127.0.0.1'; $env:FREEDOM_COMMIT_SHA = $Commit
$server = Join-Path $Release 'app\server.js'
$log = Join-Path $Root ('logs\web-' + $Port + '.log')
Set-Location -LiteralPath (Join-Path $Release 'app')
while ($true) {
    if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 10MB) {
        $null = Assert-UnderRoot $log $Root
        Move-Item -LiteralPath $log -Destination ($log + '.previous') -Force
    }
    try { Invoke-Tool $config.node @($server) $log } catch { Add-Content -LiteralPath $log -Value $_.Exception.Message }
    Start-Sleep -Seconds 5
}
