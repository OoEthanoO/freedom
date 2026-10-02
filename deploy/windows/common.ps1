# Windows PowerShell 5.1. Source checkouts and runtime state stay separate.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Assert-Administrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator access is required.' }
}
function Read-Json([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    return $null
}
function Write-AtomicText([string]$Path, [string]$Text) {
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.new'
    try {
        [IO.File]::WriteAllText($temporary, $Text, (New-Object Text.UTF8Encoding $false))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}
function Write-Json([string]$Path, $Value) { Write-AtomicText $Path ($Value | ConvertTo-Json -Depth 8) }
function Assert-UnderRoot([string]$Path, [string]$Root) {
    $resolved = [IO.Path]::GetFullPath($Path)
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Path outside runtime root: $resolved" }
    return $resolved
}
function Assert-Release([string]$Root, $State) {
    if (-not $State -or $State.taskName -notmatch '^freedom-web-[a-f0-9]{12}-\d{14}$' -or
        $State.port -notin 3400,3401 -or $State.commit -notmatch '^[a-f0-9]{40}$') { throw 'Invalid Freedom release metadata.' }
    $release = Assert-UnderRoot $State.release (Join-Path $Root 'releases')
    $expected = [IO.Path]::GetFullPath((Join-Path $Root ('releases\' + $State.taskName.Substring(12))))
    if ($release -ne $expected -or -not $State.taskName.StartsWith('freedom-web-' + $State.commit.Substring(0,12) + '-')) {
        throw 'Release path does not match its task and commit.'
    }
    return $release
}
function Invoke-Tool([string]$File, [string[]]$Arguments, [string]$Log) {
    $old = $ErrorActionPreference
    try {
        # PS 5.1 wraps native stderr as errors even for successful git/npm calls.
        $ErrorActionPreference = 'Continue'
        & $File @Arguments >> $Log 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    if ($code -ne 0) { throw "Tool failed ($code): $File. See $Log" }
}
function Get-GitOutput([string]$File, [string[]]$Arguments, [string]$Log) {
    $old = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $result = & $File @Arguments 2>> $Log
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    if ($code -ne 0) { throw "Git failed ($code). See $Log" }
    return (@($result) -join "`n").Trim()
}
function Copy-Ops([string]$Source, [string]$Destination) {
    if ([IO.Path]::GetFullPath($Source).TrimEnd('\') -eq [IO.Path]::GetFullPath($Destination).TrimEnd('\')) { return }
    foreach ($name in 'common','install','deploy','activate','run','tick','dns') {
        Copy-Item -LiteralPath (Join-Path $Source ($name + '.ps1')) -Destination $Destination -Force
    }
}
function Test-Release($State, [int]$Seconds = 45) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        try {
            $health = Invoke-RestMethod -Uri ('http://127.0.0.1:{0}/api/health' -f $State.port) -TimeoutSec 5
            if ($health.status -eq 'ok' -and $health.service -eq 'freedom' -and $health.commit -eq $State.commit) { return $true }
        } catch {}
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return $false
}
function Register-WebTask([string]$Root, $State) {
    $release = Assert-Release $Root $State
    $launcher = Join-Path $release 'ops\run.ps1'
    if (-not (Test-Path -LiteralPath (Join-Path $release 'app\server.js'))) { throw 'Standalone server is missing.' }
    $task = Get-ScheduledTask -TaskName $State.taskName -ErrorAction SilentlyContinue
    if ($task -and @($task.Actions | Where-Object { $_.Arguments -and $_.Arguments.Contains('"' + $launcher + '"') }).Count -ne 1) {
        throw 'Existing task does not belong to this release.'
    }
    $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Root "{1}" -Release "{2}" -Port {3} -Commit {4}' -f $launcher,$Root,$release,$State.port,$State.commit
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments -WorkingDirectory $release
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $State.taskName -Action $action -Trigger (New-ScheduledTaskTrigger -AtStartup) `
        -Settings $settings -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
    Start-ScheduledTask -TaskName $State.taskName
}
function Stop-WebTask([string]$Root, $State) {
    if (-not $State) { return }
    $release = Assert-Release $Root $State
    $launcher = Join-Path $release 'ops\run.ps1'
    $server = Join-Path $release 'app\server.js'
    $task = Get-ScheduledTask -TaskName $State.taskName -ErrorAction SilentlyContinue
    if ($task -and @($task.Actions | Where-Object { $_.Arguments -and $_.Arguments.Contains('"' + $launcher + '"') }).Count -ne 1) {
        throw 'Task ownership does not match this release.'
    }
    # Capture the exact process tree before stopping its launcher; never kill a port owner.
    $processes = @(Get-CimInstance Win32_Process)
    $owned = @{}
    foreach ($proc in $processes) {
        $line = [string]$proc.CommandLine
        $isLauncher = $proc.Name -ieq 'powershell.exe' -and $line.Contains('"' + $launcher + '"')
        $isServer = $proc.Name -ieq 'node.exe' -and ($line.Contains('"' + $server + '"') -or $line.EndsWith(' ' + $server))
        if ($isLauncher -or $isServer) { $owned[[int]$proc.ProcessId] = $proc }
    }
    do {
        $added = $false
        foreach ($proc in $processes) {
            $parent = $owned[[int]$proc.ParentProcessId]
            if ($parent -and -not $owned.ContainsKey([int]$proc.ProcessId) -and $proc.CreationDate -ge $parent.CreationDate) {
                $owned[[int]$proc.ProcessId] = $proc; $added = $true
            }
        }
    } while ($added)
    if ($task) { Disable-ScheduledTask -TaskName $State.taskName | Out-Null; Stop-ScheduledTask -TaskName $State.taskName }
    foreach ($proc in @($owned.Values | Sort-Object CreationDate -Descending)) {
        $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.ProcessId)"
        if ($current -and $current.CreationDate -eq $proc.CreationDate -and $current.ExecutablePath -eq $proc.ExecutablePath) {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    $deadline = (Get-Date).AddSeconds(15)
    do {
        if (-not (Get-NetTCPConnection -State Listen -LocalPort $State.port -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "Port $($State.port) remains occupied; no unrelated processes were stopped."
}
function Restore-Caddy([string]$Root, $Config, $Snapshot) {
    $sitePath = Join-Path $Root 'Caddyfile'
    $currentMain = [IO.File]::ReadAllText($Config.mainCaddyfile)
    if ($currentMain -ne $Snapshot.nextMain) { throw 'Shared Caddyfile changed concurrently; inspect it before restoring.' }
    if ($Snapshot.oldMain -ne $Snapshot.nextMain) { Write-AtomicText $Config.mainCaddyfile $Snapshot.oldMain }
    if ($null -ne $Snapshot.oldSite) { Write-AtomicText $sitePath $Snapshot.oldSite }
    elseif (Test-Path -LiteralPath $sitePath) { Remove-Item -LiteralPath (Assert-UnderRoot $sitePath $Root) -Force }
    $log = Join-Path $Root 'logs\caddy-reload.log'
    Invoke-Tool $Config.caddy @('validate','--config',$Config.mainCaddyfile,'--adapter','caddyfile') $log
    Invoke-Tool $Config.caddy @('reload','--config',$Config.mainCaddyfile,'--adapter','caddyfile') $log
}
function Switch-Caddy([string]$Root, $Config, [int]$Port) {
    if ($Port -notin 3400,3401) { throw 'Unexpected Freedom port.' }
    $sitePath = Join-Path $Root 'Caddyfile'
    $oldSite = if (Test-Path -LiteralPath $sitePath) { [IO.File]::ReadAllText($sitePath) } else { $null }
    $oldMain = [IO.File]::ReadAllText($Config.mainCaddyfile)
    $staticPath = (Join-Path $Root 'static') -replace '\\','/'
    $logPath = (Join-Path $Root 'logs\access.log') -replace '\\','/'
    $site = @"
freedom.ethanyanxu.com {
    encode zstd gzip
    header X-Freedom-Host finprint-host
    handle_path /_next/static/* {
        root * "$staticPath"
        header Cache-Control "public, max-age=31536000, immutable"
        file_server
    }
    handle {
        reverse_proxy 127.0.0.1:$Port
    }
    log {
        output file "$logPath" {
            roll_size 10MB
            roll_keep 3
        }
    }
}
"@
    $import = 'import "' + ($sitePath -replace '\\','/') + '"'
    $marker = '# BEGIN Freedom (managed)'
    $endMarker = '# END Freedom (managed)'
    $nextMain = $oldMain
    if ($oldMain.Contains($marker)) {
        if (-not $oldMain.Contains($endMarker) -or -not $oldMain.Contains($import)) { throw 'Existing Freedom Caddy import does not match this runtime.' }
    } else {
        $nextMain = $oldMain.TrimEnd() + "`r`n`r`n$marker`r`n$import`r`n$endMarker`r`n"
    }
    $snapshot = [pscustomobject]@{ oldMain=$oldMain; oldSite=$oldSite; nextMain=$nextMain }
    $stamp = (Get-Date -Format 'yyyyMMddHHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
    Write-AtomicText (Join-Path $Root ('logs\Caddyfile-before-' + $stamp)) $oldMain
    if ($null -ne $oldSite) { Write-AtomicText (Join-Path $Root ('logs\Freedom-Caddyfile-before-' + $stamp)) $oldSite }
    try {
        Write-AtomicText $sitePath $site
        if ($oldMain -ne $nextMain) {
            if ([IO.File]::ReadAllText($Config.mainCaddyfile) -ne $oldMain) { throw 'Shared Caddyfile changed concurrently.' }
            Write-AtomicText $Config.mainCaddyfile $nextMain
        }
        $log = Join-Path $Root 'logs\caddy-reload.log'
        Invoke-Tool $Config.caddy @('validate','--config',$Config.mainCaddyfile,'--adapter','caddyfile') $log
        Invoke-Tool $Config.caddy @('reload','--config',$Config.mainCaddyfile,'--adapter','caddyfile') $log
    } catch {
        $failure = $_
        try { Restore-Caddy $Root $Config $snapshot } catch { Write-Warning "Caddy rollback needs attention: $($_.Exception.Message)" }
        throw $failure
    }
    return $snapshot
}
function Set-ActiveRelease([string]$Root, $Config, $Target, $Old) {
    $null = Assert-Release $Root $Target
    if (-not (Test-Release $Target 5)) { throw 'Target release is unhealthy; traffic is unchanged.' }
    $previous = Read-Json (Join-Path $Root 'previous.json')
    $snapshot = Switch-Caddy $Root $Config $Target.port
    try {
        if ($Old -and $Old.taskName -ne $Target.taskName) { Write-Json (Join-Path $Root 'previous.json') $Old }
        Write-Json (Join-Path $Root 'active.json') $Target
    } catch {
        $failure = $_
        try {
            Restore-Caddy $Root $Config $snapshot
            foreach ($entry in @(@{name='active.json';value=$Old}, @{name='previous.json';value=$previous})) {
                $path = Join-Path $Root $entry.name
                if ($entry.value) { Write-Json $path $entry.value }
                elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath (Assert-UnderRoot $path $Root) -Force }
            }
        } catch { Write-Warning "Activation rollback needs attention: $($_.Exception.Message)" }
        throw $failure
    }
}
