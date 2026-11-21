param(
	[ValidateSet('Install', 'Uninstall', 'Init', 'Start', 'Stop', 'Status')]
	[string]$Action = 'Status',
	[string]$GameDir = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))),
	[int]$Count = 50,
	[int]$BatchSize = 10,
	[int]$BatchDelaySeconds = 30,
	[int]$MinFreeMemoryMB = 4096,
	[string]$HumanNickname = 'krory90',
	[switch]$NoWaitForHuman
)

$ErrorActionPreference = 'Stop'
$MaxBots = 50
$BotDataDir = Join-Path $env:LOCALAPPDATA 'StarConflictSolo\playerbots'
$RosterPath = Join-Path $BotDataDir 'roster.json'
$StatePath = Join-Path $BotDataDir 'fleet-state.json'
$HookSource = Join-Path $PSScriptRoot 'client-hook.lua'
$UiScripts = Join-Path $GameDir 'data\ui\scripts'
$HookTarget = Join-Path $UiScripts 'playerbots.lua'
$HookMarker = '-- SC_PLAYERBOTS_HOOK'
$HookLoadLine = "sys.execscript('ui/scripts/playerbots.lua') $HookMarker"
$MongoExe = Join-Path $GameDir 'cloud\mongodb\mongo.exe'
$GameExe = Join-Path $GameDir 'win64\game.exe'
$ZoneLogDir = Join-Path $env:LOCALAPPDATA 'Targem\StarConflict\cloud\Hub\logs'

function Write-State($Processes, $Started) {
	New-Item -ItemType Directory -Force -Path $BotDataDir | Out-Null
	[pscustomobject]@{ processes = @($Processes); startedUtc = $Started; requestedCount = $Count } |
		ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

function Get-State {
	if (-not (Test-Path -LiteralPath $StatePath)) { return $null }
	try { return Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json }
	catch { throw "Invalid bot fleet state file: $StatePath" }
}

function Get-RunningBotProcesses {
	$state = Get-State
	if (-not $state) { return @() }
	$running = @()
	foreach ($entry in $state.processes) {
		$p = Get-Process -Id ([int]$entry.pid) -ErrorAction SilentlyContinue
		if (-not $p) { continue }
		try {
			if ($p.Path -ne $GameExe) { continue }
			$started = $p.StartTime.ToUniversalTime().ToString('o')
			if ($started -ne [string]$entry.processStartedUtc) { continue }
			$running += $p
		} catch { continue }
	}
	return $running
}

function Get-ValidProcessEntries($State) {
	$valid = @()
	foreach ($entry in $State.processes) {
		$p = Get-Process -Id ([int]$entry.pid) -ErrorAction SilentlyContinue
		if (-not $p) { continue }
		try {
			if ($p.Path -ne $GameExe) { continue }
			if ($p.StartTime.ToUniversalTime().ToString('o') -ne [string]$entry.processStartedUtc) { continue }
			$valid += $entry
		} catch { continue }
	}
	return $valid
}

function Install-ClientHook {
	if (-not (Test-Path -LiteralPath $HookSource)) { throw "Client hook is missing: $HookSource" }
	if (-not (Test-Path -LiteralPath $GameExe)) { throw "Star Conflict client not found: $GameExe" }
	if (-not (Test-Path -LiteralPath $UiScripts)) { throw "Client UI scripts not found: $UiScripts" }

	New-Item -ItemType Directory -Force -Path $BotDataDir | Out-Null
	$backupDir = Join-Path $BotDataDir ('client-backup-' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
	New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

	foreach ($fileName in @('windows\loginwnd.lua', 'windows\hangarwnd.lua')) {
		$target = Join-Path $UiScripts $fileName
		if (-not (Test-Path -LiteralPath $target)) { throw "Expected client file not found: $target" }
		$bytes = [IO.File]::ReadAllBytes($target)
		$byteText = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
		if (-not $byteText.Contains($HookMarker)) {
			Copy-Item -LiteralPath $target -Destination (Join-Path $backupDir ([IO.Path]::GetFileName($fileName)))
			$append = "`r`n$HookLoadLine`r`n"
			[IO.File]::AppendAllText($target, $append, [Text.Encoding]::ASCII)
		}
	}

	Copy-Item -LiteralPath $HookSource -Destination $HookTarget -Force
	Write-Host "Installed opt-in playerbot login/zone hooks. Backup: $backupDir"
}

function Uninstall-ClientHook {
	foreach ($fileName in @('windows\loginwnd.lua', 'windows\hangarwnd.lua')) {
		$target = Join-Path $UiScripts $fileName
		if (-not (Test-Path -LiteralPath $target)) { continue }
		$text = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($target))
		$escaped = [regex]::Escape($HookLoadLine)
		$text = [regex]::Replace($text, "\r?\n$escaped\r?\n?", "`r`n")
		[IO.File]::WriteAllBytes($target, [Text.Encoding]::GetEncoding(28591).GetBytes($text))
	}
	if (Test-Path -LiteralPath $HookTarget) { Remove-Item -LiteralPath $HookTarget -Force }
	Write-Host 'Removed playerbot client hooks. Backups remain under the local playerbots data folder.'
}

function New-Roster {
	if ($Count -lt 1 -or $Count -gt $MaxBots) { throw "Count must be between 1 and $MaxBots." }
	if (Test-Path -LiteralPath $RosterPath) { throw "Roster already exists: $RosterPath. It is preserved to keep account passwords stable." }
	New-Item -ItemType Directory -Force -Path $BotDataDir | Out-Null
	$roster = @()
	for ($i = 1; $i -le $Count; $i++) {
		$login = 'SCBot{0:D3}' -f $i
		$password = [guid]::NewGuid().ToString('N') + 'aA1!'
		$secure = ConvertTo-SecureString -String $password -AsPlainText -Force
		$roster += [pscustomobject]@{ login = $login; passwordProtected = (ConvertFrom-SecureString $secure) }
	}
	$roster | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $RosterPath -Encoding UTF8
	Write-Host "Created $Count local bot identities. Passwords are DPAPI-protected for this Windows user and are not stored in the repository."
}

function Convert-ProtectedPassword([string]$Protected) {
	$secure = ConvertTo-SecureString -String $Protected
	$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
	try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
	finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Get-AccountUid([string]$Nickname) {
	if ($Nickname -notmatch '^[A-Za-z0-9_-]{1,32}$') { throw 'HumanNickname may contain only letters, digits, underscore, and hyphen.' }
	if (-not (Test-Path -LiteralPath $MongoExe)) { throw "MongoDB shell not found: $MongoExe" }
	$eval = 'var a=db.getCollection("accounts").findOne({nickName:"' + $Nickname + '"},{_id:1}); if(a){print(a._id.toString())} else {quit(4)}'
	$result = & $MongoExe --quiet '127.0.0.1/cosmosim_PC' --eval $eval 2>$null
	if ($LASTEXITCODE -ne 0 -or -not $result) { throw "Could not resolve local account '$Nickname'. Ensure the local server is running and the account exists." }
	return ([string]$result).Trim()
}

function Wait-ForHumanOpenSpace([string]$Nickname) {
	if (-not (Test-Path -LiteralPath $ZoneLogDir)) { throw "Hub log folder not found: $ZoneLogDir" }
	$uid = Get-AccountUid $Nickname
	$uidPattern = [regex]::Escape($uid)
	$offsets = @{}
	Get-ChildItem -LiteralPath $ZoneLogDir -Filter '*zone_coordinator_*.log' -File | ForEach-Object {
		$offsets[$_.FullName] = $_.Length
	}
	Write-Host "Waiting for $Nickname to enter open space; then starting a fleet of up to $Count bots in batches of $BatchSize."
	while ($true) {
		$logs = Get-ChildItem -LiteralPath $ZoneLogDir -Filter '*zone_coordinator_*.log' -File -ErrorAction SilentlyContinue
		foreach ($log in $logs) {
			$start = 0L
			if ($offsets.ContainsKey($log.FullName)) { $start = [long]$offsets[$log.FullName] }
			if ($log.Length -lt $start) { $start = 0L }
			if ($log.Length -le $start) { continue }
			$stream = [IO.File]::Open($log.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
			try {
				$stream.Position = $start
				$reader = New-Object IO.StreamReader($stream)
				$newText = $reader.ReadToEnd()
				$offsets[$log.FullName] = $stream.Length
			} finally { $stream.Dispose() }
			if ($newText -match "(?i)(starting zone \d+ for uid $uidPattern|Moving user $uidPattern to instance)") {
				Write-Host "$Nickname entered an open-world zone. Starting bots."
				return
			}
		}
		Start-Sleep -Seconds 2
	}
}

function Start-BotFleet {
	if ($Count -lt 1 -or $Count -gt $MaxBots) { throw "Count must be between 1 and $MaxBots." }
	if ($BatchSize -lt 1 -or $BatchSize -gt 10) { throw 'BatchSize must be between 1 and 10.' }
	if ($BatchDelaySeconds -lt 1) { throw 'BatchDelaySeconds must be at least 1.' }
	if (-not (Test-Path -LiteralPath $GameExe)) { throw "Game client not found: $GameExe" }
	$cloudXml = Join-Path $GameDir 'cloud\data\cloud.xml'
	if (-not (Test-Path -LiteralPath $cloudXml) -or [IO.File]::ReadAllText($cloudXml) -notmatch 'address="127\.0\.0\.1:3850"') {
		throw 'BotFleet only launches against the configured localhost server (127.0.0.1:3850).'
	}
	$hub = Get-Process Hub -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $GameDir 'cloud\Hub.exe') } | Select-Object -First 1
	if (-not $hub) { throw 'The local Star Conflict server is not running.' }
	if (-not (Test-Path -LiteralPath $RosterPath)) { New-Roster }
	$roster = @(Get-Content -LiteralPath $RosterPath -Raw | ConvertFrom-Json)
	if ($roster.Count -lt $Count) { throw "Roster contains $($roster.Count) accounts; requested $Count." }
	if (Get-RunningBotProcesses) { throw 'A BotFleet launched from this manager is already running. Use Status or Stop first.' }

	if (-not $NoWaitForHuman) { Wait-ForHumanOpenSpace $HumanNickname }

	$managed = @()
	$started = (Get-Date).ToUniversalTime().ToString('o')
	Write-State $managed $started
	for ($i = 0; $i -lt $Count; $i++) {
		$availableMB = [math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)
		if ($availableMB -lt $MinFreeMemoryMB) {
			Write-State $managed $started
			throw "Safety pause at $($managed.Count) bots: only ${availableMB}MB physical memory remains. Fleet state is saved; use Stop before retrying."
		}

		$bot = $roster[$i]
		$password = Convert-ProtectedPassword ([string]$bot.passwordProtected)
		$psi = New-Object Diagnostics.ProcessStartInfo
		$psi.FileName = $GameExe
		$psi.WorkingDirectory = Join-Path $GameDir 'win64'
		$psi.Arguments = '-multiCopies'
		$psi.UseShellExecute = $false
		$psi.EnvironmentVariables['SC_PLAYERBOT_MODE'] = '1'
		$psi.EnvironmentVariables['SC_PLAYERBOT_LOGIN'] = [string]$bot.login
		$psi.EnvironmentVariables['SC_PLAYERBOT_PASSWORD'] = $password
		$psi.EnvironmentVariables['SC_PLAYERBOT_AI_PRESET'] = 'BotsT1'
		$process = New-Object Diagnostics.Process
		$process.StartInfo = $psi
		if (-not $process.Start()) { throw "Could not start game client for $($bot.login)." }
		$managed += [pscustomobject]@{
			pid = $process.Id
			processStartedUtc = $process.StartTime.ToUniversalTime().ToString('o')
			login = [string]$bot.login
		}
		Write-State $managed $started
		$psi.EnvironmentVariables['SC_PLAYERBOT_PASSWORD'] = ''
		$password = $null
		Write-Host "Started bot client $($i + 1)/$Count (PID $($process.Id))."
		if ((($i + 1) % $BatchSize) -eq 0 -and ($i + 1) -lt $Count) {
			Start-Sleep -Seconds $BatchDelaySeconds
		}
	}
	Write-Host "Started $($managed.Count) bot clients. State: $StatePath"
}

function Stop-BotFleet {
	$state = Get-State
	if (-not $state) { Write-Host 'No managed BotFleet state found.'; return }
	$remaining = @()
	foreach ($entry in (Get-ValidProcessEntries $state)) {
		$p = Get-Process -Id ([int]$entry.pid) -ErrorAction SilentlyContinue
		if (-not $p) { continue }
		try {
			if ($p.MainWindowHandle -ne 0) { $null = $p.CloseMainWindow() }
			if (-not $p.WaitForExit(20000)) { $remaining += $entry }
		} catch { $remaining += $entry }
	}
	if ($remaining.Count -eq 0) {
		Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
		Write-Host 'All managed bot clients exited cleanly.'
	} else {
		Write-State $remaining ([string]$state.startedUtc)
		Write-Warning "These verified bot clients are still running and were left untouched: $(@($remaining | ForEach-Object pid) -join ', ')"
	}
}

switch ($Action) {
	'Install' { Install-ClientHook }
	'Uninstall' { Uninstall-ClientHook }
	'Init' { New-Roster }
	'Start' { Install-ClientHook; Start-BotFleet }
	'Stop' { Stop-BotFleet }
	'Status' {
		$state = Get-State
		$running = @(Get-RunningBotProcesses)
		if ($state) { Write-Host "Managed bots running: $($running.Count) / $($state.requestedCount). PIDs: $(@($running | ForEach-Object Id) -join ', ')" }
		else { Write-Host 'No managed bot clients are recorded.' }
	}
}
