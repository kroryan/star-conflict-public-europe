# Start the local-only server and its private MongoDB database.
param(
    [string]$GameDir = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$DbDir = (Join-Path $env:LOCALAPPDATA 'StarConflictSolo\mongodb')
)
$ErrorActionPreference = 'Stop'
$cloud = Join-Path $GameDir 'cloud'
$mongoDir = Join-Path $cloud 'mongodb'
if (-not (Test-Path -LiteralPath (Join-Path $cloud 'Hub.exe'))) { throw "Game not found in '$GameDir'." }
if (-not (Test-Path -LiteralPath (Join-Path $cloud 'data\cloud.xml'))) { throw 'cloud.xml is missing; run install-local.ps1 first.' }
if ([IO.File]::ReadAllText((Join-Path $cloud 'data\cloud.xml')) -notmatch 'address="127\.0\.0\.1:3850"') { throw 'This is not configured as a local-only server; run install-local.ps1 first.' }
if (Get-Process Hub -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$cloud\*" }) { Write-Host 'Local Star Conflict server is already running.'; exit 0 }
if (Get-Process mongod -ErrorAction SilentlyContinue) { throw 'A mongod process is already running. Stop it first so the local server cannot attach to another database.' }
New-Item -ItemType Directory -Force -Path $DbDir | Out-Null
$mongo = Start-Process -FilePath (Join-Path $mongoDir 'mongod.exe') -ArgumentList @('-f', 'config.cfg', '--dbpath', "`"$DbDir`"", '--bind_ip', '127.0.0.1') -WorkingDirectory $mongoDir -WindowStyle Hidden -PassThru
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    $client = New-Object Net.Sockets.TcpClient
    try { $client.Connect('127.0.0.1', 27017); $ready = $true; break } catch { Start-Sleep -Milliseconds 500 } finally { $client.Close() }
}
if (-not $ready) { throw "MongoDB did not start. Check process $($mongo.Id) and '$DbDir'." }
Start-Process -FilePath (Join-Path $cloud 'Hub.exe') -WorkingDirectory $cloud -WindowStyle Hidden | Out-Null
Start-Sleep -Seconds 25
if (-not (Get-Process Hub -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$cloud\*" })) { throw 'Hub exited during startup. Check %LOCALAPPDATA%\Targem\StarConflict\cloud\Hub\logs.' }
$count = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$cloud\*" }).Count
Write-Host "Local Star Conflict server started ($count server processes)."
Write-Host 'In the game login screen choose localhost. The server runs in the background until stop-local.ps1 is used.'
