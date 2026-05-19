# =============================================================================
#  build-single-bat.ps1 — Empaqueta el wizard en un .bat auto-extraíble
#
#  Lee todos los módulos, templates y perfiles, los embebe en un script
#  PowerShell dentro de un wrapper .bat, y genera:
#    - MPV-Interp-Wizard.bat (auto-extraíble)
#    - SHA256.txt (hash de verificación)
#
#  Uso:
#    powershell -ExecutionPolicy Bypass -File build-single-bat.ps1
# =============================================================================

param(
    [switch]$Test  # Solo verificar que todos los archivos existen
)

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$outBat    = Join-Path $scriptDir "MPV-Interp-Wizard.bat"
$outHash   = Join-Path $scriptDir "SHA256.txt"

# Files to embed
$filesToEmbed = @(
    @{ RelPath = "mpv-interp-wizard.ps1"; Type = "script" },
    @{ RelPath = "modules\UI.psm1"; Type = "module" },
    @{ RelPath = "modules\Config.psm1"; Type = "module" },
    @{ RelPath = "modules\GPU.psm1"; Type = "module" },
    @{ RelPath = "modules\Download.psm1"; Type = "module" },
    @{ RelPath = "modules\VapourSynth.psm1"; Type = "module" },
    @{ RelPath = "modules\VsMlrt.psm1"; Type = "module" },
    @{ RelPath = "modules\Patcher.psm1"; Type = "module" },
    @{ RelPath = "modules\Templates.psm1"; Type = "module" },
    @{ RelPath = "modules\Updater.psm1"; Type = "module" },
    @{ RelPath = "modules\Diagnostics.psm1"; Type = "module" },
    @{ RelPath = "templates\interpolation-rife.vpy"; Type = "template" },
    @{ RelPath = "templates\interpolation-mvtools.vpy"; Type = "template" },
    @{ RelPath = "templates\auto_mode.lua"; Type = "template" },
    @{ RelPath = "templates\set_display_hz.ps1"; Type = "template" },
    @{ RelPath = "profiles\gpu-profiles.json"; Type = "profile" }
)

# Verify all files exist
$missing = @()
foreach ($f in $filesToEmbed) {
    $full = Join-Path $scriptDir $f.RelPath
    if (-not (Test-Path $full)) { $missing += $f.RelPath }
}

if ($missing.Count -gt 0) {
    Write-Host "[XX] Archivos faltantes:" -ForegroundColor Red
    foreach ($m in $missing) { Write-Host "     $m" -ForegroundColor Yellow }
    exit 1
}

if ($Test) {
    Write-Host "[OK] Todos los archivos verificados ($($filesToEmbed.Count))" -ForegroundColor Green
    exit 0
}

Write-Host "==> Construyendo MPV-Interp-Wizard.bat" -ForegroundColor Cyan

# Build the .bat wrapper
$batHeader = @'
@echo off
setlocal
title MPV Interpolation Wizard
echo.
echo  Extrayendo e iniciando el wizard...
echo.

:: Create temp directory
set "TMPDIR=%TEMP%\mpv-interp-wizard"
if exist "%TMPDIR%" rmdir /s /q "%TMPDIR%"
mkdir "%TMPDIR%"
mkdir "%TMPDIR%\modules"
mkdir "%TMPDIR%\templates"
mkdir "%TMPDIR%\profiles"

:: Set home for config
set "MPV_INTERP_HOME=%~dp0"

'@

$batFooter = @'

:: Run the wizard
set "PS_CMD=powershell"
where pwsh >nul 2>&1 && set "PS_CMD=pwsh"
%PS_CMD% -ExecutionPolicy Bypass -NoProfile -File "%TMPDIR%\mpv-interp-wizard.ps1"

:: Cleanup
rmdir /s /q "%TMPDIR%" 2>nul
endlocal
'@

# Build extraction commands
$extractionLines = @()
foreach ($f in $filesToEmbed) {
    $fullPath = Join-Path $scriptDir $f.RelPath
    $content  = Get-Content $fullPath -Raw -Encoding UTF8

    # Encode to Base64 to avoid escaping issues
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($content)
    $b64    = [Convert]::ToBase64String($bytes)

    # Write as PowerShell decode command in the .bat
    $destPath = $f.RelPath -replace '\\', '\\'
    $extractionLines += "powershell -NoProfile -Command `"[IO.File]::WriteAllText('%TMPDIR%\\$($f.RelPath -replace '/', '\\')', [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64')))`""
}

$batContent = $batHeader + ($extractionLines -join "`r`n") + "`r`n" + $batFooter

Set-Content $outBat $batContent -Encoding ASCII
Write-Host "[OK] $outBat ($([math]::Round((Get-Item $outBat).Length / 1KB, 1)) KB)" -ForegroundColor Green

# Generate SHA256
$hash = (Get-FileHash $outBat -Algorithm SHA256).Hash
Set-Content $outHash "$hash  MPV-Interp-Wizard.bat" -Encoding UTF8
Write-Host "[OK] $outHash" -ForegroundColor Green
Write-Host "     $hash" -ForegroundColor DarkGray
