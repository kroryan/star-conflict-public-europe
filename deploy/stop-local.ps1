# Stop only the server processes installed in GameDir, then shut down its MongoDB cleanly.
param(
    [string]$GameDir = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)
$ErrorActionPreference = 'Stop'
$cloud = Join-Path $GameDir 'cloud'
$owned = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$cloud\*" -and $_.ProcessName -ne 'mongod' })
foreach ($process in $owned) { Stop-Process -Id $process.Id -Force }
Start-Sleep -Seconds 2
$mongoExe = Join-Path $cloud 'mongodb\mongo.exe'
if (Get-Process mongod -ErrorAction SilentlyContinue) {
    & $mongoExe --quiet 127.0.0.1/admin --eval 'db.shutdownServer()' 2>$null | Out-Null
    for ($i = 0; $i -lt 30 -and (Get-Process mongod -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 1 }
}
if (Get-Process | Where-Object { $_.Path -like "$cloud\*" }) { Write-Warning 'Some server processes are still running.' } else { Write-Host 'Local Star Conflict server stopped.' }
