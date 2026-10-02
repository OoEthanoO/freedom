# Run only on finprint-host, where the shared Cloudflare credential is protected.
[CmdletBinding()]
param(
    [string]$Root = 'C:\ProgramData\Freedom',
    [string]$SettingsPath = 'C:\ProgramData\YanLearn\secrets\cloudflare-ddns.json',
    [switch]$Rollback
)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-Administrator
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$hostname = 'freedom.ethanyanxu.com'
$target = 'finprint.ethanyanxu.com'
$backupPath = Join-Path $Root 'dns-migration.json'
$lock = [IO.File]::Open((Join-Path $Root 'dns.lock'), 'OpenOrCreate', 'ReadWrite', 'None')

function Invoke-FreedomDns([string]$Method, [string]$Path, $Body = $null) {
    $request = @{
        Uri = ('https://api.cloudflare.com/client/v4/zones/' + $settings.ZoneId + $Path)
        Method = $Method; Headers = $script:freedomDnsHeaders; TimeoutSec = 25
    }
    if ($null -ne $Body) {
        $request.Body = $Body | ConvertTo-Json -Compress
        $request.ContentType = 'application/json'
    }
    try { $response = Invoke-RestMethod @request }
    catch { throw 'Cloudflare request failed. Check connectivity and the protected credential.' }
    if (-not $response.success) { throw 'Cloudflare did not accept the DNS request.' }
    return $response.result
}

try {
    $settings = Read-Json $SettingsPath
    if ($settings.ZoneId -notmatch '^[a-f0-9]{32}$') { throw 'Invalid Cloudflare zone ID.' }
    Add-Type -AssemblyName System.Security
    $plain = [Security.Cryptography.ProtectedData]::Unprotect(
        [Convert]::FromBase64String([IO.File]::ReadAllText($settings.TokenPath)), $null,
        [Security.Cryptography.DataProtectionScope]::LocalMachine)
    $script:freedomDnsHeaders = @{Authorization = ('Bearer ' + [Text.Encoding]::UTF8.GetString($plain))}
    [Array]::Clear($plain, 0, $plain.Length)
    $current = @(Invoke-FreedomDns 'GET' ('/dns_records?name=' + $hostname))
    $backup = Read-Json $backupPath

    # A POST may succeed even if its response or the following state write is lost.
    if ($backup -and -not $backup.recordId -and $backup.hostname -eq $hostname -and
        $backup.target -eq $target -and @($backup.previousExplicitRecords).Count -eq 0 -and
        $current.Count -eq 1 -and $current[0].type -eq 'CNAME' -and
        $current[0].content -eq $target -and -not $current[0].proxied -and
        $current[0].comment -eq 'Freedom on finprint-host; follows the existing home-server DDNS record.') {
        $backup.recordId = $current[0].id
        Write-Json $backupPath $backup
    }

    if ($Rollback) {
        if (-not $backup -or -not $backup.recordId) { throw 'No recorded Freedom DNS change to roll back.' }
        if ($current.Count -eq 0) { Write-Output 'The Freedom DNS override is already absent.'; return }
        if ($current.Count -ne 1 -or $current[0].id -ne $backup.recordId -or
            $current[0].name -ne $hostname -or $current[0].type -ne 'CNAME' -or
            $current[0].content -ne $target -or $current[0].proxied) {
            throw 'Freedom DNS has changed since migration; refusing to remove it.'
        }
        $null = Invoke-FreedomDns 'DELETE' ('/dns_records/' + $backup.recordId)
        if (@(Invoke-FreedomDns 'GET' ('/dns_records?name=' + $hostname)).Count -ne 0) {
            throw 'DNS rollback verification failed.'
        }
        Write-Output 'Removed only the Freedom DNS override; the existing wildcard applies again.'
        return
    }

    $active = Read-Json (Join-Path $Root 'active.json')
    if (-not $active -or -not (Test-Release $active 10)) { throw 'Activate a healthy Freedom release before switching DNS.' }
    if ($current.Count -eq 1 -and $current[0].type -eq 'CNAME' -and
        $current[0].content -eq $target -and -not $current[0].proxied) {
        Write-Output 'Freedom DNS already points to finprint-host.'
        return
    }
    if ($current.Count -ne 0) { throw 'An unexpected explicit Freedom DNS record exists; inspect before replacing it.' }
    $wildcard = @(Invoke-FreedomDns 'GET' '/dns_records?name=%2A.ethanyanxu.com')
    if ($wildcard.Count -ne 1 -or $wildcard[0].type -ne 'CNAME' -or
        $wildcard[0].content -ne 'cname.vercel-dns-017.com') {
        throw 'The expected Vercel wildcard has changed; inspect DNS before migrating.'
    }
    # Keep the previous routing evidence before adding the narrowly scoped override.
    Write-Json $backupPath ([ordered]@{
        hostname = $hostname; target = $target; previousExplicitRecords = @()
        wildcard = $wildcard[0]; changedAt = [DateTime]::UtcNow.ToString('o'); recordId = $null
    })
    $created = Invoke-FreedomDns 'POST' '/dns_records' @{
        type = 'CNAME'; name = $hostname; content = $target; ttl = 60; proxied = $false
        comment = 'Freedom on finprint-host; follows the existing home-server DDNS record.'
    }
    $backup = Read-Json $backupPath
    $backup.recordId = $created.id
    Write-Json $backupPath $backup
    $verified = @(Invoke-FreedomDns 'GET' ('/dns_records?name=' + $hostname))
    if ($verified.Count -ne 1 -or $verified[0].id -ne $created.id -or
        $verified[0].content -ne $target -or $verified[0].proxied) { throw 'DNS cutover verification failed.' }
    Write-Output 'freedom.ethanyanxu.com now follows finprint.ethanyanxu.com (DNS only, TTL 60).'
} finally {
    $script:freedomDnsHeaders = $null
    if ($lock) { $lock.Dispose() }
}
