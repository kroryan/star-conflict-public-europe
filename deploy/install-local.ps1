# Apply this kit's local-only matchmaking config to an existing Steam install.
param(
    [string]$GameDir = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$DbDir = (Join-Path $env:LOCALAPPDATA 'StarConflictSolo\mongodb')
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $PSScriptRoot 'files\cloud\data\default_platform_config.lua'
$target = Join-Path $GameDir 'cloud\data\default_platform_config.lua'
$cloudXml = Join-Path $GameDir 'cloud\data\cloud.xml'
if (-not (Test-Path -LiteralPath (Join-Path $GameDir 'cloud\Hub.exe'))) { throw "Star Conflict server files not found in '$GameDir'." }
if (-not (Test-Path -LiteralPath $source)) { throw "Config not found in the kit: '$source'." }
if (Get-Process Hub -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$(Join-Path $GameDir 'cloud')\*" }) { throw 'Stop the local server before installing or updating its config.' }

& (Join-Path $PSScriptRoot 'configure-solo.ps1')
$backup = Join-Path $env:LOCALAPPDATA ('StarConflictSolo\backups\' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $backup, $DbDir | Out-Null
if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination (Join-Path $backup 'default_platform_config.lua') }
if (Test-Path -LiteralPath $cloudXml) { Copy-Item -LiteralPath $cloudXml -Destination (Join-Path $backup 'cloud.xml') }
Copy-Item -LiteralPath $source -Destination $target -Force

# Advertise only loopback. No firewall rule is opened by this local installer.
$xml = [IO.File]::ReadAllText($cloudXml)
$xml = [regex]::Replace($xml, '(?i)(<Node\b[^>]*\baddress=")[^"]*"', '${1}127.0.0.1:3850"', 1)
if ($xml -notmatch 'address="127\.0\.0\.1:3850"') { throw 'Could not set the local-only address in cloud.xml.' }
[IO.File]::WriteAllText($cloudXml, $xml, [Text.UTF8Encoding]::new($false))
Write-Host "Local bot profile installed. Game: $GameDir"
Write-Host "Local MongoDB data: $DbDir"
Write-Host 'The login address remains localhost; this installer does not open network ports.'
