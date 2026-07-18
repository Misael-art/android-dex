[CmdletBinding()]
param([switch]$EnableStartup)
$ErrorActionPreference = 'Stop'
$source = Split-Path -Parent $MyInvocation.MyCommand.Path
$app = Join-Path $env:LOCALAPPDATA 'AndroidDex'
$config = Join-Path $env:APPDATA 'AndroidDex'
New-Item -ItemType Directory -Force -Path $app,$config | Out-Null
Copy-Item -Force (Join-Path $source 'android-dex.ps1') (Join-Path $app 'android-dex.ps1')
Copy-Item -Force (Join-Path $source 'uninstall.ps1') (Join-Path $app 'uninstall.ps1')
if (-not (Test-Path (Join-Path $config 'config.ps1'))) {
    Copy-Item (Join-Path $source 'config.ps1.example') (Join-Path $config 'config.ps1')
}
foreach ($tool in @('adb','scrcpy')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Write-Warning "$tool nao esta no PATH; instale Android platform-tools/scrcpy antes de executar." }
}
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Android DEX.lnk'))
$shortcut.TargetPath = 'powershell.exe'
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $app 'android-dex.ps1') + '"'
$shortcut.WorkingDirectory = $app; $shortcut.Save()
if ($EnableStartup) {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $app 'android-dex.ps1') + '"')
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    Register-ScheduledTask -TaskName 'AndroidDEX' -Action $action -Trigger $trigger -Description 'Supervisor Android-DEX do usuario' -Force | Out-Null
}
Write-Host "Android-DEX instalado em $app" -ForegroundColor Green
Write-Host "Config: $(Join-Path $config 'config.ps1')"
