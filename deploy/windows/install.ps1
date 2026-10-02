[CmdletBinding()]
param([string]$Root = 'C:\ProgramData\Freedom', [Parameter(Mandatory)][string]$CaddyExe,
    [Parameter(Mandatory)][string]$MainCaddyfile, [switch]$EnableAutoDeploy)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-Administrator
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
if ($Root -eq [IO.Path]::GetPathRoot($Root).TrimEnd('\') -or $Root -eq $env:USERPROFILE -or $Root -eq $env:ProgramData) { throw 'Use a dedicated runtime directory.' }
foreach ($name in 'logs','releases','static','ops') { New-Item -ItemType Directory -Path (Join-Path $Root $name) -Force | Out-Null }
$lock = [IO.File]::Open((Join-Path $Root 'deploy.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    & icacls.exe $Root '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not protect the runtime directory.' }
    $config = [pscustomobject]@{
        node=(Get-Command node.exe).Source; npm=(Get-Command npm.cmd).Source; git=(Get-Command git.exe).Source
        caddy=(Resolve-Path -LiteralPath $CaddyExe).Path; mainCaddyfile=(Resolve-Path -LiteralPath $MainCaddyfile).Path
    }
    Write-Json (Join-Path $Root 'server.json') $config
    $repo = Join-Path $Root 'repo'
    $log = Join-Path $Root 'logs\install.log'
    if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) {
        Invoke-Tool $config.git @('clone','--branch','main','https://github.com/OoEthanoO/freedom.git',$repo) $log
    }
    $gitOptions = @('-c', ('safe.directory=' + ($repo -replace '\\','/')), '-C', $repo)
    $origin = Get-GitOutput $config.git ($gitOptions + @('remote','get-url','origin')) $log
    if ($origin -ne 'https://github.com/OoEthanoO/freedom.git') { throw 'Runtime checkout has an unexpected origin.' }
    $ops = Join-Path $Root 'ops'
    Copy-Ops $PSScriptRoot $ops
    if ($EnableAutoDeploy) {
        $active = Read-Json (Join-Path $Root 'active.json')
        $null = Assert-Release $Root $active
        if (-not (Test-Release $active 5)) { throw 'Activate and verify a release before enabling automatic deployment.' }
        $launcher = Join-Path $ops 'tick.ps1'
        $existing = Get-ScheduledTask -TaskName 'freedom-deploy' -ErrorAction SilentlyContinue
        if ($existing -and @($existing.Actions | Where-Object { $_.Arguments -and $_.Arguments.Contains('"' + $launcher + '"') }).Count -ne 1) { throw 'Existing freedom-deploy task belongs to a different runtime.' }
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Root "{1}"' -f $launcher,$Root)
        $triggers = @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 2)))
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 25) `
            -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName 'freedom-deploy' -Action $action -Trigger $triggers -Settings $settings -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
    }
    Write-Output "Runtime installed at $Root."
} finally { $lock.Dispose() }
