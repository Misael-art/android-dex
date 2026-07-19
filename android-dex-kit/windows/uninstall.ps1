[CmdletBinding()]
param([switch]$Purge)
$ErrorActionPreference = 'SilentlyContinue'
$app = Join-Path $env:LOCALAPPDATA 'AndroidDex'
$config = Join-Path $env:APPDATA 'AndroidDex'
$script = Join-Path $app 'android-dex.ps1'
if (Test-Path $script) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Command stop 2>$null }
Unregister-ScheduledTask -TaskName 'AndroidDEX' -Confirm:$false
Remove-Item -Force (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Android DEX.lnk')
if ($Purge) { Remove-Item -Recurse -Force $app,$config }
else {
    Remove-Item -Force (Join-Path $app 'android-dex.ps1'),(Join-Path $app 'uninstall.ps1')
    Write-Host "Config e estado preservados. Use -Purge para remove-los: $config"
}
