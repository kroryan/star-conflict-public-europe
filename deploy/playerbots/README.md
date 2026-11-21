# Experimental client fleet launcher

This is an **unverified experiment**, not a completed open-world playerbot system. It can prepare up to 50 local account identities and attempt to start separate game clients after the configured human account enters open space. A successful login or zone entry does not make a ship autonomous. The released server exposes no supported API in this repository for attaching NPC combat AI to a real player session, and the client hook deliberately does not call guessed AI functions.

The launcher is opt-in and restricted to the local server address `127.0.0.1:3850`. It stores generated passwords in a DPAPI-protected roster under `%LOCALAPPDATA%\StarConflictSolo\playerbots`, outside the repository. Keep that file: it is required for later logins. Each client still uses substantial memory; the default free-memory floor is 4 GB and the launch pauses when it is reached. A batch size of 10 is a ceiling, not a promise that the machine can run 50 clients.

The server's internal auto-create option must be enabled (`auth_allowInternalAutoCreate = 1`) for first-time generated accounts. This is enabled by the local profile in this checkout; verify it remains enabled in other server installs.

## Commands

Run these yourself from the game directory in PowerShell. `Install` appends opt-in loader lines to two local UI scripts and keeps timestamped backups outside the repository.

```powershell
$manager = '.\community-server-kit\deploy\playerbots\BotFleet.ps1'
powershell -ExecutionPolicy Bypass -File $manager -Action Install -GameDir (Get-Location).Path
powershell -ExecutionPolicy Bypass -File $manager -Action Init -Count 50 -GameDir (Get-Location).Path
```

Start after the local server is running. By default, the manager waits for `krory90` to enter open space before launching clients in batches of at most 10, 30 seconds apart.

```powershell
powershell -ExecutionPolicy Bypass -File $manager -Action Start -Count 50 -BatchSize 10 -GameDir (Get-Location).Path
```

To update the repo-managed hook later, pull the fork and run `Start` again; it copies the current hook and avoids adding duplicate loader lines.

```powershell
git -C .\community-server-kit pull --ff-only origin main
powershell -ExecutionPolicy Bypass -File $manager -Action Install -GameDir (Get-Location).Path
```

Inspect or stop only processes recorded by this manager:

```powershell
powershell -ExecutionPolicy Bypass -File $manager -Action Status -GameDir (Get-Location).Path
powershell -ExecutionPolicy Bypass -File $manager -Action Stop -GameDir (Get-Location).Path
```

`Stop` requests a normal window close and leaves any client that does not exit alone. The state file records executable path and process start time as well as PID, so a recycled PID will not be treated as one of these clients. To remove the hooks, run `-Action Uninstall`; backups are retained.

## Current limits

- The game build must permit multiple processes with `-multiCopies`; this switch has not been verified against the current build.
- The Lua runtime must expose `os.getenv` for per-process credentials. If it does not, the hook logs that automation is disabled and leaves the normal login flow intact.
- The open-space request path is a client-side experiment and has not been validated against the local server.
- No autonomous movement, combat, missions, corporations, chat, or other player behavior is implemented by this launcher.
- Do not expose the server publicly while testing generated accounts. These identities are only for the local solo instance.

Promote this from experiment only after one client is verified end to end: authenticated account, visible pilot in the correct zone, clean disconnect, and measured resource use. Autonomous behavior needs a supported bot-session API or a separately validated protocol client; neither is provided here.
