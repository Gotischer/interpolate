# =============================================================================
#  build-single-bat.ps1 — Empaqueta el wizard en un .bat auto-extraible
#
#  Estrategia: Comprime todo en un .zip, lo codifica en Base64, lo divide
#  en chunks de 4000 chars (dentro del limite de CMD de 8191) y genera un
#  .bat que reconstruye el .zip y lo extrae via PowerShell.
# =============================================================================

param(
    [switch]$Test  # Solo verificar que todos los archivos existen
)

$ErrorActionPreference = "Stop"

$scriptDir  = $PSScriptRoot
$outBat     = Join-Path $scriptDir "MPV-Interp-Wizard.bat"
$outHash    = Join-Path $scriptDir "SHA256.txt"
$chunkSize  = 4000  # Max chars per echo line (well under CMD's 8191 limit)

# Files to embed
$filesToEmbed = @(
    "mpv-interp-wizard.ps1",
    "modules\UI.psm1",
    "modules\Config.psm1",
    "modules\GPU.psm1",
    "modules\Download.psm1",
    "modules\VapourSynth.psm1",
    "modules\VsMlrt.psm1",
    "modules\Patcher.psm1",
    "modules\Templates.psm1",
    "modules\Updater.psm1",
    "modules\Diagnostics.psm1",
    "templates\interpolation-rife.vpy",
    "templates\interpolation-mvtools.vpy",
    "templates\auto_mode.lua",
    "templates\set_display_hz.ps1",
    "profiles\gpu-profiles.json"
)

# Verify all files exist
$missing = @()
foreach ($f in $filesToEmbed) {
    $full = Join-Path $scriptDir $f
    if (-not (Test-Path $full)) { $missing += $f }
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

# Step 1: Create a temporary .zip with all files
$tempZip = Join-Path $env:TEMP "mpv-interp-wizard-build.zip"
if (Test-Path $tempZip) { Remove-Item $tempZip -Force }

# Create temp staging directory with proper structure
$staging = Join-Path $env:TEMP "mpv-interp-wizard-staging"
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Path $staging | Out-Null
New-Item -ItemType Directory -Path (Join-Path $staging "modules") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $staging "templates") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $staging "profiles") | Out-Null

foreach ($f in $filesToEmbed) {
    $src = Join-Path $scriptDir $f
    $dst = Join-Path $staging $f
    Copy-Item $src $dst -Force
}

Compress-Archive -Path "$staging\*" -DestinationPath $tempZip -Force
Write-Host "     ZIP creado: $([math]::Round((Get-Item $tempZip).Length / 1KB, 1)) KB" -ForegroundColor Gray

# Step 2: Convert ZIP to Base64 and split into chunks
$zipBytes = [System.IO.File]::ReadAllBytes($tempZip)
$b64      = [Convert]::ToBase64String($zipBytes)
$chunks   = @()

for ($i = 0; $i -lt $b64.Length; $i += $chunkSize) {
    $len   = [Math]::Min($chunkSize, $b64.Length - $i)
    $chunk = $b64.Substring($i, $len)
    $chunks += $chunk
}

Write-Host "     Base64: $($b64.Length) chars en $($chunks.Count) chunks" -ForegroundColor Gray

# Step 3: Build the .bat file
$batLines = @()

# --- BAT header ---
$batLines += '@echo off'
$batLines += 'setlocal enabledelayedexpansion'
$batLines += 'title MPV Interpolation Wizard'
$batLines += 'echo.'
$batLines += 'echo  MPV Interpolation Wizard - Extrayendo...'
$batLines += 'echo.'
$batLines += ''
$batLines += 'set "TMPDIR=%TEMP%\mpv-interp-wizard"'
$batLines += 'set "MPV_INTERP_HOME=%~dp0"'
$batLines += 'set "B64FILE=%TMPDIR%\payload.b64"'
$batLines += 'set "ZIPFILE=%TMPDIR%\payload.zip"'
$batLines += ''
$batLines += 'if exist "%TMPDIR%" rmdir /s /q "%TMPDIR%"'
$batLines += 'mkdir "%TMPDIR%"'
$batLines += ''
$batLines += ':: Write Base64 payload to file (chunked to avoid CMD line length limit)'
$batLines += 'echo. > "%B64FILE%"'

# --- Write chunks (using >> append) ---
# First chunk uses > to overwrite, rest use >> to append
for ($i = 0; $i -lt $chunks.Count; $i++) {
    $op = if ($i -eq 0) { '>' } else { '>>' }
    # Use echo with <nul set /p to avoid trailing newline and CRLF issues
    $batLines += ('<nul set /p="' + $chunks[$i] + '" ' + $op + ' "%B64FILE%"')
}

$batLines += ''
$batLines += ':: Decode Base64 and extract ZIP via PowerShell'
$batLines += 'set "PS_CMD=powershell"'
$batLines += 'where pwsh >nul 2>&1 && set "PS_CMD=pwsh"'
$batLines += ''
$batLines += ':: Write extraction script (avoids escaping issues with inline commands)'
$batLines += 'set "EXTRACTOR=%TMPDIR%\extract.ps1"'
$batLines += '> "%EXTRACTOR%" echo $d = $env:TEMP + ''\mpv-interp-wizard'''
$batLines += '>> "%EXTRACTOR%" echo $b64 = Get-Content (Join-Path $d ''payload.b64'') -Raw'
$batLines += '>> "%EXTRACTOR%" echo $bytes = [Convert]::FromBase64String($b64.Trim())'
$batLines += '>> "%EXTRACTOR%" echo $zip = Join-Path $d ''payload.zip'''
$batLines += '>> "%EXTRACTOR%" echo [IO.File]::WriteAllBytes($zip, $bytes)'
$batLines += '>> "%EXTRACTOR%" echo Expand-Archive -Path $zip -DestinationPath $d -Force'
$batLines += '>> "%EXTRACTOR%" echo Remove-Item (Join-Path $d ''payload.b64''), $zip -Force -EA SilentlyContinue'
$batLines += ''
$batLines += '%PS_CMD% -NoProfile -ExecutionPolicy Bypass -File "%EXTRACTOR%"'
$batLines += ''
$batLines += 'if not exist "%TMPDIR%\mpv-interp-wizard.ps1" ('
$batLines += '    echo [ERROR] Fallo la extraccion. Intenta ejecutar como administrador.'
$batLines += '    pause'
$batLines += '    exit /b 1'
$batLines += ')'
$batLines += ''
$batLines += 'echo  Iniciando wizard...'
$batLines += 'echo.'
$batLines += ''
$batLines += ':: Run the wizard'
$batLines += '%PS_CMD% -NoProfile -ExecutionPolicy Bypass -File "%TMPDIR%\mpv-interp-wizard.ps1"'
$batLines += ''
$batLines += ':: Cleanup'
$batLines += 'rmdir /s /q "%TMPDIR%" 2>nul'
$batLines += 'endlocal'

# Write .bat file
$batContent = $batLines -join "`r`n"
[System.IO.File]::WriteAllText($outBat, $batContent, [System.Text.Encoding]::ASCII)

# Cleanup staging
Remove-Item $staging -Recurse -Force -EA SilentlyContinue
Remove-Item $tempZip -Force -EA SilentlyContinue

$batSize = (Get-Item $outBat).Length
Write-Host "[OK] $outBat ($([math]::Round($batSize / 1KB, 1)) KB)" -ForegroundColor Green

# Generate SHA256
$hash = (Get-FileHash $outBat -Algorithm SHA256).Hash
Set-Content $outHash "$hash  MPV-Interp-Wizard.bat" -Encoding UTF8
Write-Host "[OK] $outHash" -ForegroundColor Green
Write-Host "     $hash" -ForegroundColor DarkGray
