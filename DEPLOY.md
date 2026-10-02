# Freedom on finprint-host

Production URL: https://freedom.ethanyanxu.com

Freedom runs on the Windows home server reached by `ssh finprint-host`. It uses
the server's existing Caddy HTTPS proxy and a standalone Next.js server bound to
loopback. No database, application secrets, or Vercel runtime services are needed.

## Runtime layout

- `C:\ProgramData\Freedom\repo`: deployment checkout of this repository.
- `releases\<commit>-<timestamp>\app`: independent standalone builds.
- `ops`: installed deployment scripts.
- `active.json`, `previous.json`, `prepared.json`: release state and rollback targets.
- `server.json`: absolute executable paths and the shared Caddy configuration path.
- `Caddyfile`: Freedom's site snippet, imported by the existing Finprint Caddyfile.
- `static`: retained immutable Next.js assets for browsers spanning a release switch.
- `logs`: build, application, proxy, and deployment poller logs.

The runtime directory is restricted to SYSTEM and Administrators. App tasks named
`freedom-web-<commit>-<timestamp>` start at boot and recover from process failures.
The active release uses either `127.0.0.1:3400` or `127.0.0.1:3401`; updates build
and pass readiness checks on the other port before Caddy switches traffic.
Builds and runtime use `America/Toronto` for server-side calendar calculations.

## First install

Run these commands in an elevated PowerShell session **on finprint-host**, from a
checkout of this repository:

```powershell
.\deploy\windows\install.ps1 `
  -CaddyExe 'C:\Users\ethan\AppData\Local\Microsoft\WinGet\Links\caddy.exe' `
  -MainCaddyfile 'C:\Users\ethan\finprint\scripts\selfhost\Caddyfile'

& 'C:\ProgramData\Freedom\ops\deploy.ps1' -PrepareOnly
```

Check the port in `prepared.json`. Verify `/api/health`, `/`, the share pages
such as `/winter/days`, and `/winter/days/opengraph-image` on that port. Then:

```powershell
& 'C:\ProgramData\Freedom\ops\activate.ps1'
& 'C:\ProgramData\Freedom\ops\dns.ps1'
```

The DNS script adds only the explicit, DNS-only Cloudflare record
`freedom.ethanyanxu.com CNAME finprint.ethanyanxu.com` with a 60-second TTL. Freedom
previously inherited `*.ethanyanxu.com CNAME cname.vercel-dns-017.com`; the wildcard
is left intact. The existing `ethanyanxu-cloudflare-ddns` task maintains the
Finprint address, so Freedom follows home IP changes automatically.

The script uses the existing DPAPI-protected Cloudflare credential referenced by
`C:\ProgramData\YanLearn\secrets\cloudflare-ddns.json`. It never copies credentials
into this repository. DNS migration evidence and the created record ID are saved
in `C:\ProgramData\Freedom\dns-migration.json`.

Caddy obtains and renews the certificate using the existing router forwarding
for ports 80/443. Wait for the public URL to return a valid HTTPS response and
`X-Freedom-Host: finprint-host`, then enable automatic deployment:

```powershell
& 'C:\ProgramData\Freedom\ops\install.ps1' `
  -CaddyExe 'C:\Users\ethan\AppData\Local\Microsoft\WinGet\Links\caddy.exe' `
  -MainCaddyfile 'C:\Users\ethan\finprint\scripts\selfhost\Caddyfile' `
  -EnableAutoDeploy
```

## Updates and verification

Push to GitHub `main`. The `freedom-deploy` scheduled task checks every two minutes,
installs the lockfile dependencies, builds a separate release, verifies its health,
and reloads Caddy. Failed builds do not replace the active release. To deploy now:

```powershell
Start-ScheduledTask -TaskName freedom-deploy
Get-Content 'C:\ProgramData\Freedom\logs\poller.log' -Tail 40
Invoke-RestMethod https://freedom.ethanyanxu.com/api/health
```

The health response identifies `service: freedom`, `status: ok`, and the deployed
Git commit. `vercel.json` disables Vercel's automatic Git deployments. Existing
Vercel deployments are retained; no Vercel project is deleted during migration.

## Rollback

To return to the previous healthy home-server release:

```powershell
Disable-ScheduledTask -TaskName freedom-deploy
& 'C:\ProgramData\Freedom\ops\activate.ps1' -Rollback
```

Keep the poller disabled until the unwanted commit is reverted on `main`, or it
will deploy that commit again. Re-enable it with `Enable-ScheduledTask` afterward.

For DNS rollback only, `dns.ps1 -Rollback` removes the exact Freedom record created
by this migration after checking its identity and target. This restores wildcard
routing to Vercel; it does **not** restore a disabled Vercel deployment. Confirm
Vercel is serving successfully before using that rollback.

Do not regenerate the shared Finprint Caddyfile without preserving all imported
sites. Freedom's import is marked `# BEGIN Freedom (managed)`. Its activation
script backs up the shared file, validates the full configuration, and reloads
Caddy without restarting other hosted apps.

References: [Next.js self-hosting](https://nextjs.org/docs/14/app/building-your-application/deploying),
[Caddy reload](https://caddyserver.com/docs/command-line#caddy-reload), and
[Vercel Git deployment control](https://vercel.com/docs/project-configuration/git-configuration#git.deploymentenabled).
