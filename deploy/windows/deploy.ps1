[CmdletBinding()]
param([string]$Root = 'C:\ProgramData\Freedom', [string]$Ref = 'origin/main', [switch]$PrepareOnly)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-Administrator
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$lock = $null; $next = $null; $keepRunning = $false
$oldLocation = Get-Location
$oldNodeEnv = $env:NODE_ENV; $oldPath = $env:PATH; $oldTimeZone = $env:TZ
try {
    $lock = [IO.File]::Open((Join-Path $Root 'deploy.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $config = Read-Json (Join-Path $Root 'server.json')
    if (-not $config) { throw 'Run install.ps1 first.' }
    $repo = Join-Path $Root 'repo'
    $log = Join-Path $Root 'logs\deploy.log'
    $env:NEXT_TELEMETRY_DISABLED = '1'; $env:GIT_TERMINAL_PROMPT = '0'
    $env:TZ = 'America/Toronto'
    $env:PATH = (Split-Path $config.node) + ';' + $env:PATH
    $gitOptions = @('-c', ('safe.directory=' + ($repo -replace '\\','/')), '-C', $repo)
    $origin = Get-GitOutput $config.git ($gitOptions + @('remote','get-url','origin')) $log
    if ($origin -ne 'https://github.com/OoEthanoO/freedom.git') { throw 'Runtime checkout has an unexpected origin.' }
    Invoke-Tool $config.git ($gitOptions + @('fetch','origin','main')) $log
    $commit = Get-GitOutput $config.git ($gitOptions + @('rev-parse','--verify','--end-of-options',($Ref + '^{commit}'))) $log
    if ($commit -notmatch '^[a-f0-9]{40}$') { throw 'Invalid revision.' }
    $active = Read-Json (Join-Path $Root 'active.json')
    if ($active) { $null = Assert-Release $Root $active }
    if ($active -and $active.commit -eq $commit -and (Test-Release $active 5)) { Write-Output "Already serving $commit"; return }
    $port = if ($active -and $active.port -eq 3400) { 3401 } else { 3400 }
    if (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) { throw "Port $port is occupied. Inspect saved/prepared releases before deploying." }
    $dirty = Get-GitOutput $config.git ($gitOptions + @('status','--porcelain')) $log
    if ($dirty) { throw 'Deployment checkout is not clean; refusing to overwrite it.' }
    Invoke-Tool $config.git ($gitOptions + @('checkout','--detach',$commit)) $log
    Set-Location -LiteralPath $repo
    $env:NODE_ENV = 'development'
    Invoke-Tool $config.npm @('ci','--include=dev','--no-audit','--no-fund') $log
    $env:NODE_ENV = 'production'
    Invoke-Tool $config.npm @('run','build') $log
    if (-not (Test-Path -LiteralPath (Join-Path $repo '.next\standalone\server.js'))) { throw 'Build did not emit a Next.js standalone server.' }
    $releaseId = $commit.Substring(0,12) + '-' + (Get-Date -Format 'yyyyMMddHHmmss')
    $release = Assert-UnderRoot (Join-Path $Root ('releases\' + $releaseId)) (Join-Path $Root 'releases')
    if (Test-Path -LiteralPath $release) { throw 'Release directory already exists; retry after inspecting it.' }
    $app = Join-Path $release 'app'
    New-Item -ItemType Directory -Path $app,(Join-Path $release 'ops') | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $repo '.next\standalone') -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $app -Recurse -Force }
    if (Test-Path -LiteralPath (Join-Path $repo 'public')) { Copy-Item -LiteralPath (Join-Path $repo 'public') -Destination (Join-Path $app 'public') -Recurse -Force }
    Copy-Item -LiteralPath (Join-Path $repo '.next\static') -Destination (Join-Path $app '.next\static') -Recurse -Force
    Copy-Ops (Join-Path $repo 'deploy\windows') (Join-Path $release 'ops')
    # Retain hashed assets for browser tabs that span multiple releases.
    Get-ChildItem -LiteralPath (Join-Path $repo '.next\static') -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Root 'static') -Recurse -Force }
    $next = [pscustomobject]@{commit=$commit;release=$release;port=$port;taskName=('freedom-web-'+$releaseId);createdAt=(Get-Date).ToUniversalTime().ToString('o')}
    Write-Json (Join-Path $release 'release.json') $next
    Register-WebTask $Root $next
    if (-not (Test-Release $next)) { throw 'Readiness failed. Existing traffic is unchanged.' }
    if ($PrepareOnly) {
        Write-Json (Join-Path $Root 'prepared.json') $next
        $keepRunning = $true
        Write-Output "Prepared $commit on loopback $port."
        return
    }
    Set-ActiveRelease $Root $config $next $active
    $keepRunning = $true
    Copy-Ops (Join-Path $release 'ops') (Join-Path $Root 'ops')
    if ($active) { Start-Sleep -Seconds 20; Stop-WebTask $Root $active }
    Write-Output "Serving $commit on port $port."
} finally {
    try {
        if ($next -and -not $keepRunning) {
            $serving = Read-Json (Join-Path $Root 'active.json')
            if (-not $serving -or $serving.taskName -ne $next.taskName) { Stop-WebTask $Root $next }
        }
    } finally {
        if ($lock) { $lock.Dispose() }
        Set-Location -LiteralPath $oldLocation.Path
        $env:NODE_ENV = $oldNodeEnv; $env:PATH = $oldPath; $env:TZ = $oldTimeZone
    }
}
