# Android-DEX for Windows 10/11 - supervisor resiliente sobre adb + scrcpy.
# Compativel com Windows PowerShell 5.1 e PowerShell 7+.
[CmdletBinding()]
param(
    [ValidateSet('run', 'list', 'status', 'stop', 'restore-tweaks')]
    [string]$Command = 'run',
    [ValidateSet('', 'auto', 'usb', 'wifi')]
    [string]$Connection = '',
    [ValidateSet('', 'auto', 'dex', 'mirror')]
    [string]$Mode = '',
    [string]$Device = '',
    [string]$Ip = '',
    [switch]$Once,
    [switch]$NoAudio
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AppDir = Join-Path $env:LOCALAPPDATA 'AndroidDex'
$script:StateDir = Join-Path $script:AppDir 'state'
$script:ConfigDir = Join-Path $env:APPDATA 'AndroidDex'
$script:ConfigFile = Join-Path $script:ConfigDir 'config.ps1'
$script:StateFile = Join-Path $script:StateDir 'supervisor.json'
$script:LogFile = Join-Path $script:StateDir 'android-dex.log'
New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null

# Defaults. O config usa nomes Adx* para nao sobrescrever parametros da CLI.
$AdxMode = 'auto'; $AdxConnection = 'auto'; $AdxDeviceIp = ''; $AdxDeviceSerial = ''
$AdxDisplayRes = '1920x1080'; $AdxDisplayDpi = 160; $AdxMaxFps = 60
$AdxVideoBitrate = '8M'; $AdxAudio = $true; $AdxStayAwake = $true
$AdxTurnScreenOff = $false; $AdxEnableFreeformTweaks = $true
$AdxRestoreTweaksOnExit = $false; $AdxReconnect = $true
$AdxBackoffBase = 2; $AdxBackoffCap = 30; $AdxHealthySessionSeconds = 15
$AdxAutoDexMinSdk = 35; $AdxWindowTitle = 'Android DEX'; $AdxStartApp = ''
$AdxVdSystemDecorations = $true; $AdxExtraArgs = @(); $AdxDebug = $false
if (Test-Path -LiteralPath $script:ConfigFile) { . $script:ConfigFile }
if ($Mode) { $AdxMode = $Mode }; if ($Connection) { $AdxConnection = $Connection }
if ($Device) { $AdxDeviceSerial = $Device }; if ($Ip) { $AdxDeviceIp = $Ip; $AdxConnection = 'wifi' }
if ($NoAudio) { $AdxAudio = $false }; if ($Once) { $AdxReconnect = $false }

$script:Child = $null; $script:SelectedSerial = ''; $script:TweaksApplied = $false

function Write-AdxLog([string]$Level, [string]$Message) {
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    if ($Level -eq 'ERRO') { Write-Host $line -ForegroundColor Red }
    elseif ($Level -eq 'WARN') { Write-Host $line -ForegroundColor Yellow }
    elseif ($Level -eq 'OK') { Write-Host $line -ForegroundColor Green }
    elseif ($Level -eq 'DEBUG') { if ($AdxDebug) { Write-Host $line -ForegroundColor DarkGray } }
    else { Write-Host $line }
}

function Require-Tool([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Ferramenta ausente no PATH: $Name" }
}

function Invoke-Quiet([scriptblock]$Action, [string]$Description) {
    try { & $Action | Out-Null; return $true }
    catch { if ($AdxDebug) { Write-AdxLog DEBUG "$Description falhou: $($_.Exception.Message)" }; return $false }
}

function Get-AdbDevices {
    $result = @()
    $lines = @(& adb devices -l 2>$null)
    foreach ($line in $lines) {
        if ($line -match '^([^\s]+)\s+([^\s]+)(.*)$' -and $Matches[1] -ne 'List') {
            $serial = $Matches[1]; $state = $Matches[2]; $details = $Matches[3]
            $model = '-'; if ($details -match 'model:([^\s]+)') { $model = $Matches[1] }
            $transport = if ($serial -match ':[0-9]+$') { 'Wi-Fi' } else { 'USB' }
            $result += [pscustomobject]@{ Serial=$serial; State=$state; Transport=$transport; Model=$model }
        }
    }
    return @($result)
}

function Show-Devices {
    $devices = @(Get-AdbDevices)
    if ($devices.Count -eq 0) { Write-Host 'Nenhum aparelho detectado.'; return }
    $i = 0; $devices | ForEach-Object { $i++; [pscustomobject]@{'#'=$i;Serial=$_.Serial;Estado=$_.State;Conexao=$_.Transport;Modelo=$_.Model} } | Format-Table -AutoSize
}

function Test-SerialOnline([string]$Serial) {
    return @((Get-AdbDevices) | Where-Object { $_.Serial -eq $Serial -and $_.State -eq 'device' }).Count -eq 1
}

function Select-Device {
    if ($AdxDeviceSerial) {
        if (-not (Test-SerialOnline $AdxDeviceSerial)) { throw "Serial explicito '$AdxDeviceSerial' nao esta online." }
        return $AdxDeviceSerial
    }
    $online = @((Get-AdbDevices) | Where-Object { $_.State -eq 'device' })
    if ($AdxConnection -eq 'usb') { $online = @($online | Where-Object { $_.Transport -eq 'USB' }) }
    elseif ($AdxConnection -eq 'wifi') { $online = @($online | Where-Object { $_.Transport -eq 'Wi-Fi' }) }
    else {
        $usb = @($online | Where-Object { $_.Transport -eq 'USB' })
        if ($usb.Count -gt 0) { $online = $usb } else { $online = @($online | Where-Object { $_.Transport -eq 'Wi-Fi' }) }
    }
    if ($online.Count -eq 0 -and $AdxDeviceIp) {
        Write-AdxLog INFO "Conectando por Wi-Fi em $AdxDeviceIp"
        & adb connect $AdxDeviceIp 2>$null | Out-Null; Start-Sleep -Seconds 1
        if (Test-SerialOnline $AdxDeviceIp) { return $AdxDeviceIp }
    }
    if ($online.Count -eq 0) { return '' }
    if ($online.Count -eq 1) { return $online[0].Serial }
    Write-AdxLog WARN 'Ha varios aparelhos online; escolha sem risco de troca silenciosa:'
    for ($i=0; $i -lt $online.Count; $i++) { Write-Host ('  {0}) {1} ({2}, {3})' -f ($i+1),$online[$i].Serial,$online[$i].Transport,$online[$i].Model) }
    $answer = Read-Host "Numero do aparelho (1-$($online.Count), vazio cancela)"
    if ($answer -notmatch '^[0-9]+$' -or [int]$answer -lt 1 -or [int]$answer -gt $online.Count) { throw 'Selecao cancelada ou invalida.' }
    return $online[[int]$answer-1].Serial
}

function Get-DeviceProp([string]$Serial, [string]$Key) {
    return ((& adb -s $Serial shell getprop $Key 2>$null) -join '').Trim()
}

function Resolve-Mode([string]$Serial) {
    if ($AdxMode -ne 'auto') { return $AdxMode }
    $sdkText = Get-DeviceProp $Serial 'ro.build.version.sdk'; $sdk = 0
    [void][int]::TryParse($sdkText, [ref]$sdk)
    $identity = ((Get-DeviceProp $Serial 'ro.product.manufacturer') + ' ' + (Get-DeviceProp $Serial 'ro.product.brand')).ToLowerInvariant()
    $secondary = ((& adb -s $Serial shell cmd package has-feature android.software.activities_on_secondary_displays 2>$null) -join '').Trim()
    if ($sdk -ge $AdxAutoDexMinSdk -and ($identity.Contains('samsung') -or $secondary -eq 'true')) {
        Write-AdxLog OK "Modo automatico: display virtual habilitado (SDK $sdk)."; return 'dex'
    }
    Write-AdxLog WARN "Modo automatico: capacidade desktop nao confirmada (SDK $sdk); usando mirror."; return 'mirror'
}

function Get-SnapshotPath([string]$Serial) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Serial)))).Replace('-','').Substring(0,16) }
    finally { $sha.Dispose() }
    return Join-Path $script:StateDir "tweaks-$hash.json"
}

function Save-Tweaks([string]$Serial) {
    $path = Get-SnapshotPath $Serial; if (Test-Path -LiteralPath $path) { return }
    $values = @{}; foreach ($key in @('enable_freeform_support','force_desktop_mode_on_external_displays','enable_non_resizable_multi_window')) {
        $value = ((& adb -s $Serial shell settings get global $key 2>$null) -join '').Trim()
        if ($LASTEXITCODE -ne 0) { throw "Nao consegui ler o ajuste $key; nenhum tweak foi aplicado." }
        $values[$key] = if ($value -eq 'null') { $null } else { $value }
    }
    $tmp = "$path.$PID.tmp"; @{format='android-dex-tweaks-v1';serial=$Serial;values=$values} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -Force -LiteralPath $tmp -Destination $path
    Write-AdxLog WARN "Ajustes persistem no aparelho; estado anterior salvo. Use -Command restore-tweaks -Device $Serial."
}

function Apply-Tweaks([string]$Serial, [string]$RuntimeMode) {
    if ($RuntimeMode -ne 'dex' -or -not $AdxEnableFreeformTweaks) { return }
    Save-Tweaks $Serial
    foreach ($key in @('enable_freeform_support','force_desktop_mode_on_external_displays','enable_non_resizable_multi_window')) {
        & adb -s $Serial shell settings put global $key 1 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-AdxLog WARN "Falha ao aplicar $key." }
    }
    $script:TweaksApplied = $true
}

function Restore-Tweaks([string]$Serial, [bool]$Required=$true) {
    $path = Get-SnapshotPath $Serial
    if (-not (Test-Path -LiteralPath $path)) { if ($Required) { throw "Sem snapshot de tweaks para $Serial." }; return }
    $snapshot = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    if ($snapshot.format -ne 'android-dex-tweaks-v1' -or $snapshot.serial -ne $Serial) { throw 'Snapshot de tweaks invalido ou pertence a outro aparelho.' }
    $failed = 0; foreach ($key in @('enable_freeform_support','force_desktop_mode_on_external_displays','enable_non_resizable_multi_window')) {
        $value = $snapshot.values.$key
        if ($null -eq $value) { & adb -s $Serial shell settings delete global $key 2>$null | Out-Null }
        else { & adb -s $Serial shell settings put global $key ([string]$value) 2>$null | Out-Null }
        if ($LASTEXITCODE -ne 0) { $failed++ }
    }
    if ($failed -gt 0) { throw "$failed ajuste(s) nao puderam ser restaurados; snapshot preservado." }
    Remove-Item -LiteralPath $path -Force; $script:TweaksApplied = $false; Write-AdxLog OK 'Ajustes anteriores restaurados.'
}

function Quote-ProcessArg([string]$Value) { return '"' + $Value.Replace('"','\"') + '"' }

function Start-Scrcpy([string]$Serial, [string]$RuntimeMode) {
    $args = @('-s',$Serial,"--window-title=$AdxWindowTitle",'--max-fps',"$AdxMaxFps",'--video-bit-rate',"$AdxVideoBitrate")
    if ($AdxStayAwake) { $args += '--stay-awake' }; if (-not $AdxAudio) { $args += '--no-audio' }
    if ($RuntimeMode -eq 'dex') {
        $args += "--new-display=$AdxDisplayRes/$AdxDisplayDpi"; $args += '--no-vd-destroy-content'
        if (-not $AdxVdSystemDecorations) { $args += '--no-vd-system-decorations' }; if ($AdxStartApp) { $args += "--start-app=$AdxStartApp" }
    } elseif ($AdxTurnScreenOff) { $args += '--turn-screen-off' }
    $args += @($AdxExtraArgs)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command scrcpy).Source; $psi.UseShellExecute = $false
    $psi.Arguments = (($args | ForEach-Object { Quote-ProcessArg ([string]$_) }) -join ' ')
    $script:Child = New-Object Diagnostics.Process; $script:Child.StartInfo = $psi
    Write-AdxLog OK "Iniciando $RuntimeMode em $Serial"; [void]$script:Child.Start(); Write-State $Serial $script:Child.Id
    $started = Get-Date; $script:Child.WaitForExit(); $duration = [int]((Get-Date)-$started).TotalSeconds; $rc = $script:Child.ExitCode
    $script:Child.Dispose(); $script:Child = $null; Write-State $Serial 0; return @{Rc=$rc;Duration=$duration}
}

function Write-State([string]$Serial, [int]$ChildPid=0) {
    $tmp = "$script:StateFile.$PID.tmp"
    @{pid=$PID;child_pid=$ChildPid;serial=$Serial;script=$PSCommandPath} | ConvertTo-Json | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -Force -LiteralPath $tmp -Destination $script:StateFile
}

function Test-StateOwner($State) {
    try {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($State.pid)" -ErrorAction Stop
        return $proc.CommandLine -like '*android-dex.ps1*'
    } catch { return $false }
}

function Test-ScrcpyProcess([int]$ProcessId) {
    try {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
        return $proc.Name -like 'scrcpy*' -or $proc.CommandLine -like '*scrcpy*'
    } catch { return $false }
}

function Stop-Supervisor {
    if (-not (Test-Path -LiteralPath $script:StateFile)) { Write-AdxLog WARN 'Nenhuma sessao ativa.'; return }
    $state = Get-Content -Raw -LiteralPath $script:StateFile | ConvertFrom-Json
    if (-not (Test-StateOwner $state)) { Remove-Item -Force -LiteralPath $script:StateFile; throw 'Estado obsoleto removido; PID nao pertencia ao Android-DEX.' }
    if ($state.child_pid -gt 0 -and (Test-ScrcpyProcess ([int]$state.child_pid))) {
        Stop-Process -Id $state.child_pid -ErrorAction SilentlyContinue
    }
    Stop-Process -Id $state.pid -ErrorAction Stop; Write-AdxLog OK "Supervisor $($state.pid) encerrado."
}

if ($Command -eq 'list') { Require-Tool adb; & adb start-server 2>$null | Out-Null; Show-Devices; exit 0 }
if ($Command -eq 'status') {
    if (Test-Path -LiteralPath $script:StateFile) { Get-Content -Raw -LiteralPath $script:StateFile } else { Write-Host 'Supervisor inativo.' }
    exit 0
}
if ($Command -eq 'stop') { Stop-Supervisor; exit 0 }

Require-Tool adb; Require-Tool scrcpy; & adb start-server 2>$null | Out-Null
$mutex = New-Object Threading.Mutex($false, 'Local\AndroidDex.Supervisor')
if (-not $mutex.WaitOne(0)) { throw 'Android-DEX ja esta em execucao. Use -Command status ou stop.' }
try {
    $script:SelectedSerial = Select-Device
    if (-not $script:SelectedSerial) { throw 'Nenhum aparelho online.' }
    if ($Command -eq 'restore-tweaks') { Restore-Tweaks $script:SelectedSerial; exit 0 }
    Write-State $script:SelectedSerial
    $attempt = 0; $fallbackUsed = $false
    while ($true) {
        if (-not (Test-SerialOnline $script:SelectedSerial)) {
            if (-not $AdxReconnect) { throw "Aparelho $script:SelectedSerial desconectado." }
            if ($script:SelectedSerial -match ':[0-9]+$') { & adb connect $script:SelectedSerial 2>$null | Out-Null }
            $delay = [Math]::Min($AdxBackoffCap, $AdxBackoffBase * [Math]::Pow(2,[Math]::Min($attempt,5)))
            Write-AdxLog WARN "Sem aparelho; nova tentativa em $delay s."; Start-Sleep -Seconds $delay; $attempt++; continue
        }
        $runtimeMode = Resolve-Mode $script:SelectedSerial; Apply-Tweaks $script:SelectedSerial $runtimeMode
        $result = Start-Scrcpy $script:SelectedSerial $runtimeMode
        if ($AdxMode -eq 'auto' -and $runtimeMode -eq 'dex' -and -not $fallbackUsed -and $result.Rc -ne 0 -and $result.Duration -lt $AdxHealthySessionSeconds) {
            $fallbackUsed = $true; $AdxMode = 'mirror'; if ($script:TweaksApplied) { Restore-Tweaks $script:SelectedSerial $false }
            Write-AdxLog WARN 'Display virtual falhou rapidamente; tentando mirror.'; continue
        }
        if ($Once -or -not $AdxReconnect) { break }
        if ($result.Duration -ge $AdxHealthySessionSeconds) { $attempt = 0 }
        $delay = [Math]::Min($AdxBackoffCap, $AdxBackoffBase * [Math]::Pow(2,[Math]::Min($attempt,5)))
        Write-AdxLog WARN "Sessao caiu (rc=$($result.Rc)); recuperando em $delay s."; Start-Sleep -Seconds $delay; $attempt++
    }
}
finally {
    if ($script:Child -and -not $script:Child.HasExited) { $script:Child.Kill() }
    if ($AdxRestoreTweaksOnExit -and $script:TweaksApplied -and $script:SelectedSerial) { try { Restore-Tweaks $script:SelectedSerial $false } catch { Write-AdxLog ERRO $_.Exception.Message } }
    if (Test-Path -LiteralPath $script:StateFile) { Remove-Item -Force -LiteralPath $script:StateFile -ErrorAction SilentlyContinue }
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
