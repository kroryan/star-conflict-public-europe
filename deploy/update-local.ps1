# Pull the fork's latest config, preserve backups, and reapply it to the local Steam install.
param(
    [string]$GameDir = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$DbDir = (Join-Path $env:LOCALAPPDATA 'StarConflictSolo\mongodb')
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (Get-Process Hub -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$(Join-Path $GameDir 'cloud')\*" }) { throw 'Run stop-local.ps1 before updating.' }
git -C $repo pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed. Resolve local changes before retrying; nothing was copied to the game.' }
& (Join-Path $PSScriptRoot 'install-local.ps1') -GameDir $GameDir -DbDir $DbDir
