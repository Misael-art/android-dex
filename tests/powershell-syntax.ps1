$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failed = $false
Get-ChildItem -Path (Join-Path $root 'android-dex-kit/windows') -Filter '*.ps1' | ForEach-Object {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $failed = $true
        $errors | ForEach-Object { Write-Error "$($_.Extent.File):$($_.Extent.StartLineNumber): $($_.Message)" -ErrorAction Continue }
    } else { Write-Host "ok - PowerShell parser: $($_.Name)" }
}
if ($failed) { exit 1 }
