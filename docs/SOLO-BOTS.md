# Local solo server with bots

This profile is for one human pilot on a private localhost server. It uses the bot and matchmaking support already present in Star Conflict; it does not create simulated user accounts.

## Install and run

From PowerShell in the repository folder:

```powershell
.\deploy\install-local.ps1 -GameDir 'C:\Program Files (x86)\Steam\steamapps\common\star conflict'
.\deploy\start-local.ps1 -GameDir 'C:\Program Files (x86)\Steam\steamapps\common\star conflict'
```

At the client login screen, select **localhost** and create a local account. The server advertises `127.0.0.1`; the install script opens no firewall ports. MongoDB data is stored under `%LOCALAPPDATA%\StarConflictSolo\mongodb`, separately from Steam files.

Stop the server cleanly before shutting down Windows or updating:

```powershell
.\deploy\stop-local.ps1 -GameDir 'C:\Program Files (x86)\Steam\steamapps\common\star conflict'
```

## Easy update from this fork

1. Stop the local server with `stop-local.ps1`.
2. Run `update-local.ps1 -GameDir 'C:\Program Files (x86)\Steam\steamapps\common\star conflict'`.
3. Start it again with `start-local.ps1`.

The update script fast-forwards this checkout from `origin/main`, reapplies the solo profile, backs up the current matchmaking config and `cloud.xml` under `%LOCALAPPDATA%\StarConflictSolo\backups`, then copies the config into the Steam install. It does not replace the account database. If a Steam update or file verification restores the stock config, run `install-local.ps1` again.

## What the profile does

- PvP arena queues request 24 total participants (one pilot and up to 23 bots); vs-AI queues use the fork's 16-participant setup.
- Training and regular PvE queues can start with one pilot. Brawls request bots up to each mode's configured capacity; one-against-all keeps its native seven-bot setup.
- Queue wait is shortened, raid wing minimums are lowered, and sector/league queues allow bots where the server configuration exposes that option.
- The server stays local-only. Other computers cannot join through the advertised address.

## Limits: bots are not player accounts

These are battle AI ships. They can fight in a battle when that mode and mission script support bot slots. They do not log in as pilots, stand in the hangar, chat, trade, join corporations, or independently travel around the open-world map. Open-world NPCs continue to follow the game's existing scripts. Some brawls, raids, PvE objectives and sector features may still refuse to start or may not be playable solo; changing queue sizes cannot give the AI new mission logic. The fork's [known issues](KNOWN_ISSUES.md) also documents bot preset limitations.

This repo is the source of truth for the local matchmaking config. Keep future solo-mode edits in `deploy/files/cloud/data/default_platform_config.lua` and rerun `configure-solo.ps1` after pulling upstream changes.
