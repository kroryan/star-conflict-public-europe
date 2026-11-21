# Reapply the solo-bots profile to the upstream matchmaking config.
$ErrorActionPreference = 'Stop'
$config = Join-Path $PSScriptRoot 'files\cloud\data\default_platform_config.lua'
$encoding = [Text.Encoding]::GetEncoding(1251)
$text = [IO.File]::ReadAllText($config, $encoding)
$start = $text.IndexOf('local queuesConfigLo = {')
$end = $text.IndexOf('-- high on-line', $start)
if ($start -lt 0 -or $end -lt 0) { throw 'Could not find the low-online matchmaking block.' }
$low = $text.Substring($start, $end - $start)

# Supported PvP, practice and mission queues start with one human and fill with AI.
$low = $low.Replace('special = { gameMode = 5, botsCount = 0 },', 'special = { gameMode = 5, botsCount = 10 },')
$low = $low.Replace('special = { pve = 1, gameMode = 7 },', 'special = { pve = 1, gameMode = 7, botsCount = 4 },')
$low = $low.Replace('special = { arcade = 1, botsCount = 8 }', 'special = { arcade = 1, botsCount = 24 }')
$low = $low.Replace('special = { arcade = 1, botsCount = 8, botPresetNames', 'special = { arcade = 1, botsCount = 24, botPresetNames')
$low = $low.Replace('maxTimeInQueue = 60,', 'maxTimeInQueue = 5,')
$low = $low.Replace('optimalPlayers = 4,', 'optimalPlayers = 1,')
$low = $low.Replace('maxPlayers = 16 } ) )', 'maxPlayers = 24 } ) )')
# Keep the vs-AI queue size at the kit's tested 16 participants.
$low = $low.Replace('special = { botsCount = 16, botPresetNames = { "BotsT1" }, queueFlags = { newbie = 1, }, }, maxPlayers = 24 } ) )', 'special = { botsCount = 16, botPresetNames = { "BotsT1" }, queueFlags = { newbie = 1, }, }, maxPlayers = 16 } ) )')

$brawls = @(
    @{ Name = 'footballQueueTemplate'; Count = 6; Mode = 'brawl' },
    @{ Name = 'gtdmQueueTemplate'; Count = 2; Mode = 'brawl' },
    @{ Name = 'atdmQueueTemplate'; Count = 8; Mode = 'brawl' },
    @{ Name = 'sentinelQueueTemplate'; Count = 24; Mode = 'brawl' },
    @{ Name = 'captureTheBaseQueueTemplate'; Count = 24; Mode = 'brawl' },
    @{ Name = 'hangerGamesQueueTemplate'; Count = 24; Mode = 'hunger_games' },
    @{ Name = 'aprilTeamDeathMatchQueueTemplate'; Count = 24; Mode = 'brawl' },
    @{ Name = 'zombieQueueTemplate'; Count = 24; Mode = 'zombie' },
    @{ Name = 'closeDistanceQueueTemplate'; Count = 24; Mode = 'close_distance' },
    @{ Name = 'autogenDmGamesQueueTemplate'; Count = 24; Mode = 'hunger_games' },
    @{ Name = 'threeTeamsDeathMatchTemplate'; Count = 24; Mode = 'three_teams_dm' },
    @{ Name = 'aprilControlQueueTemplate'; Count = 8; Mode = 'brawl' }
)

foreach ($queue in $brawls) {
    $pattern = '(?s)(local ' + [regex]::Escape($queue.Name) + '\s*=\s*\{)(.*?)(\n\s*\})'
    $match = [regex]::Match($low, $pattern)
    if (-not $match.Success) { throw "Could not find queue template $($queue.Name)." }
    $body = $match.Groups[2].Value
    $count = [string]$queue['Count']
    $body = [regex]::Replace($body, '(?m)(\s*maxPlayers\s*=\s*)\d+(,)', [Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + $count + $m.Groups[2].Value }, 1)
    $body = [regex]::Replace($body, '(?m)(\s*optimalPlayers\s*=\s*)\d+(,)', [Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + '1' + $m.Groups[2].Value }, 1)
    $body = [regex]::Replace($body, '(?m)(\s*minPlayers\s*=\s*)\d+(,)', [Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + '1' + $m.Groups[2].Value }, 1)
    $replacement = $match.Groups[1].Value + $body + $match.Groups[3].Value
    $low = $low.Substring(0, $match.Index) + $replacement + $low.Substring($match.Index + $match.Length)

    # Match the queue through its nested levelsDesc table to reach special.
    $mode = [string]$queue['Mode']
    $specialPattern = '(?s)(local ' + [regex]::Escape($queue.Name) + '\s*=\s*\{.*?special\s*=\s*\{\s*' + [regex]::Escape($mode) + '\s*=\s*1)(?:,\s*botsCount\s*=\s*\d+)?(\s*\})'
    $specialMatch = [regex]::Match($low, $specialPattern)
    if (-not $specialMatch.Success) { throw "Could not find special settings for $($queue.Name)." }
    $specialReplacement = $specialMatch.Groups[1].Value + ', botsCount = ' + $count + $specialMatch.Groups[2].Value
    $low = $low.Substring(0, $specialMatch.Index) + $specialReplacement + $low.Substring($specialMatch.Index + $specialMatch.Length)
}

# One-against-all is a special 1-vs-7 mode; keep its seven-bot limit.
$oneVsAll = '(?s)(local oneAgainstAllQueueTemplate\s*=\s*\{.*?optimalPlayers\s*=\s*)\d+(,\s*minPlayers\s*=\s*)\d+'
$low = [regex]::Replace($low, $oneVsAll, [Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + '1' + $m.Groups[2].Value + '1' }, 1)
$text = $text.Substring(0, $start) + $low + $text.Substring($end)
$text = [regex]::Replace($text, '(?m)(cvars\.mm_botsCount\s*=\s*)6', [Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + '23' }, 1)
$text = [regex]::Replace($text, '(?m)(minSizeWing\s*=\s*)\d+', [Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + '1' })
$text = [regex]::Replace($text, '(?m)(minSizeTeam\s*=\s*)4', [Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + '1' }, 1)
$text = $text.Replace('withBots = false,', 'withBots = true,')
$text = $text.Replace('special = { pve_raid = 1, gameMode = 7 },', 'special = { pve_raid = 1, gameMode = 7, botsCount = 12 },')
$text = [regex]::Replace($text, '(?m)(mm_raidMinWingSize\s*=\s*)10', [Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + '1' + $m.Groups[2].Value }, 1)
[IO.File]::WriteAllText($config, $text, $encoding)
Write-Host 'Solo-bots matchmaking profile applied to the repository config.'
