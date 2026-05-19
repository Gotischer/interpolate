# =============================================================================
#  mpv-interp-wizard.ps1
#
#  Wizard interactivo para instalar/actualizar/reparar interpolación de frames
#  en mpv usando VapourSynth + RIFE (TensorRT) o MVTools (fallback CPU).
#
#  Uso:
#    powershell -ExecutionPolicy Bypass -File mpv-interp-wizard.ps1
# =============================================================================

$ErrorActionPreference = "Stop"
$ProgressPreference    = "Continue"

# --- Versioning --------------------------------------------------------------
$Global:WizardVersion       = "2.0.0"
$Global:VpyTemplateVersion  = 1
$Global:LuaTemplateVersion  = 1
$Global:SetHzTemplateVersion = 1

# --- Determine script root (works from .bat too) -----------------------------
$wizardRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }

# --- Import modules -----------------------------------------------------------
$modulesDir = Join-Path $wizardRoot "modules"
Import-Module (Join-Path $modulesDir "UI.psm1")          -Force -DisableNameChecking
Import-Module (Join-Path $modulesDir "Config.psm1")       -Force -DisableNameChecking
Import-Module (Join-Path $modulesDir "GPU.psm1")          -Force -DisableNameChecking
Import-Module (Join-Path $modulesDir "Download.psm1")     -Force -DisableNameChecking
Import-Module (Join-Path $modulesDir "VapourSynth.psm1")  -Force -DisableNameChecking
Import-Module (Join-Path $modulesDir "VsMlrt.psm1")       -Force -DisableNameChecking
Import-Module (Join-Path $modulesDir "Patcher.psm1")      -Force -DisableNameChecking
Import-Module (Join-Path $modulesDir "Templates.psm1")    -Force -DisableNameChecking
Import-Module (Join-Path $modulesDir "Updater.psm1")      -Force -DisableNameChecking
Import-Module (Join-Path $modulesDir "Diagnostics.psm1")  -Force -DisableNameChecking

# --- Start transcript for logging ---------------------------------------------
try {
    $logDir = Split-Path (Get-ConfigFilePath) -Parent
    if (-not (Test-Path $logDir)) { $logDir = $wizardRoot }
    $logFile = Join-Path $logDir "mpv-interp-wizard.log"
    Start-Transcript -Path $logFile -Append -EA SilentlyContinue | Out-Null
} catch {}

# =============================================================================
# WELCOME SCREEN
# =============================================================================
function Show-Welcome {
    Clear-Host
    Write-Title "MPV Interpolation Wizard v$Global:WizardVersion"
    Write-Host ""
    Write-Host "  Este asistente instala interpolación de frames en mpv." -ForegroundColor White
    Write-Host "  Convierte video de 24/30 fps a la frecuencia de tu monitor" -ForegroundColor White
    Write-Host "  (60/120/144 Hz) para movimiento fluido." -ForegroundColor White
    Write-Host ""
    Write-Host "  Qué va a pasar:" -ForegroundColor Cyan
    Write-Host "    1. Detecta tu GPU y elige el mejor backend" -ForegroundColor Gray
    Write-Host "       • NVIDIA RTX 20-50  → RIFE con TensorRT (calidad alta)" -ForegroundColor DarkGray
    Write-Host "       • AMD / Intel Arc   → RIFE con NCNN/Vulkan" -ForegroundColor DarkGray
    Write-Host "       • iGPU / sin GPU    → MVTools (CPU, calidad básica)" -ForegroundColor DarkGray
    Write-Host "    2. Te pregunta dónde instalar (~5-7 GB)" -ForegroundColor Gray
    Write-Host "    3. Descarga e instala VapourSynth + RIFE + modelos" -ForegroundColor Gray
    Write-Host "    4. Configura mpv para usarlo automáticamente" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Características:" -ForegroundColor Cyan
    Write-Host "    • Soporte HDR (interpolación + Hz switch)" -ForegroundColor Gray
    Write-Host "    • Detección multi-monitor (60Hz + 120Hz)" -ForegroundColor Gray
    Write-Host "    • Scene detection (evita artifacts en cortes)" -ForegroundColor Gray
    Write-Host "    • Toggle con Ctrl+i, diagnóstico con Ctrl+Shift+d" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Cancela con Q o Esc en cualquier menú." -ForegroundColor DarkGray
    Write-Host ""
    $r = Read-Host "  Presiona Enter para continuar, Q para salir"
    if ($r -eq "q" -or $r -eq "Q") { exit 0 }
}

# =============================================================================
# FIRST-TIME SETUP
# =============================================================================
function Invoke-FirstTimeSetup {
    Clear-Host
    Write-Title "CONFIGURACIÓN INICIAL"
    Write-Host "  Primera vez. Configura las rutas (puedes cambiarlas después)." -ForegroundColor White
    Write-Host ""

    # Auto-detect mpv
    $detectedMpv = Find-MpvExe
    if ($detectedMpv) { Write-Ok "mpv detectado: $detectedMpv" }
    else              { Write-Info "mpv no detectado automáticamente" }
    $config.MpvExe = Read-PathPrompt -Label "Ruta a mpv.exe" -Default $detectedMpv -MustExist $true

    # Auto-detect portable_config
    $detectedConfig = Find-PortableConfig -MpvExePath $config.MpvExe
    if ($detectedConfig) { Write-Ok "Config detectado: $detectedConfig" }
    $config.MpvConfigDir = Read-PathPrompt -Label "Carpeta portable_config de mpv" -Default $detectedConfig -MustExist $false

    # BaseDir
    Write-Host ""
    $detectedBase = Find-BaseDir -MpvExePath $config.MpvExe
    if ($detectedBase) {
        Write-Ok "VapourSynth detectado en: $detectedBase"
        $defaultBase = $detectedBase
    } else {
        $mpvParent = Split-Path $config.MpvExe -Parent
        $defaultBase = Split-Path $mpvParent -Parent
        if ($defaultBase) { $defaultBase = Join-Path $defaultBase "mpv-interp" }
        else { $defaultBase = "C:\mpv-interp" }
        Write-Info "BaseDir: donde se instalará VapourSynth + vs-mlrt (~5-7 GB)"
    }
    $config.BaseDir = Read-PathPrompt -Label "Carpeta de instalación (BaseDir)" -Default $defaultBase -MustExist $false

    # Local bundle (optional)
    Write-Host ""
    Write-Info "Si ya tienes los .7z de vs-mlrt descargados, indica la carpeta"
    $config.LocalBundleDir = Read-PathPrompt -Label 'Carpeta con .7z descargados, o Enter para omitir' -Default '' -AllowEmpty $true

    if (Export-WizardConfig -Config $config -Path $configPath) {
        Write-Ok "Configuración guardada en $configPath"
    }
    Wait-Continue
}

# =============================================================================
# INSTALL FLOW
# =============================================================================
function Invoke-Install {
    Clear-Host
    Write-Title "INSTALACIÓN COMPLETA"

    # 1) GPU detection
    Write-Section "Detectando GPU"
    foreach ($line in (Format-GPUInfo $gpuEnv)) { Write-Info $line }

    $profile = Get-GPUProfile -ProfileKey $gpuEnv.ProfileKey -ProfilesPath (Join-Path $wizardRoot "profiles\gpu-profiles.json")
    Write-Info "Perfil: $($profile.label)"
    Write-Host ""

    $backendType = switch ($gpuEnv.SupportedBackend) {
        "RIFE_TRT"  { "TRT" }
        "RIFE_NCNN" { "NCNN_VK" }
        default     { "MVTOOLS" }
    }

    # 2) VapourSynth
    $vsDir = Install-VapourSynth -Config $config -TargetRelease $config.VsRelease

    if ($backendType -ne "MVTOOLS") {
        # 3) vs-mlrt
        $mlrtTag = Install-VsMlrt -Config $config -BackendType $backendType -VsDir $vsDir

        # 4) Patch vsmlrt.py
        $vsmlrtPy = Join-Path $vsDir "Lib\site-packages\vsmlrt.py"
        if (Test-Path $vsmlrtPy) {
            Backup-VsmlrtPy -Path $vsmlrtPy
            Invoke-VsmlrtPatch -Path $vsmlrtPy
        }

        # 5) RIFE models
        $modelsToInstall = @($profile.model)
        if ($profile.model -ne "v4.25") { $modelsToInstall += "v4.25" }  # Always include standard as fallback
        Install-RIFEModels -Config $config -VsDir $vsDir -Models $modelsToInstall
    }

    # 6) Generate config files
    New-InterpolationVpy -BackendType $backendType -Profile $profile -Config $config `
        -DestDir $config.MpvConfigDir -Force -WizardVersion $Global:WizardVersion `
        -VpyTemplateVersion $Global:VpyTemplateVersion

    $concurrent = if ($profile.streams -eq 1) { 1 } else { 4 }
    New-AutoModeLua -Config $config -DestDir $config.MpvConfigDir -Force `
        -Buffered 8 -Concurrent $concurrent `
        -WizardVersion $Global:WizardVersion -LuaTemplateVersion $Global:LuaTemplateVersion

    New-SetDisplayHz -Config $config -DestDir $config.MpvConfigDir -Force `
        -WizardVersion $Global:WizardVersion -SetHzTemplateVersion $Global:SetHzTemplateVersion

    # 7) Update config with installed versions
    if ($mlrtTag) { $config.MlrtVersion = $mlrtTag }
    Export-WizardConfig -Config $config -Path $configPath | Out-Null

    Write-Host ""
    Write-Title "¡INSTALACIÓN COMPLETA!"
    Write-Host "  Abre cualquier video con mpv y disfruta." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Atajos en mpv:" -ForegroundColor Cyan
    Write-Host "    Ctrl+i       → Toggle interpolación ON/OFF" -ForegroundColor Gray
    Write-Host "    Ctrl+h       → Toggle interpolación HDR ON/OFF" -ForegroundColor Gray
    Write-Host "    Ctrl+Shift+d → Mostrar info de diagnóstico" -ForegroundColor Gray
    Write-Host ""
    Wait-Continue
}

# =============================================================================
# REPAIR FLOW
# =============================================================================
function Invoke-Repair {
    Clear-Host
    Write-Title "REPARAR INSTALACIÓN"

    $items = @(
        "Regenerar interpolation.vpy",
        "Regenerar auto_mode.lua",
        "Re-parchear vsmlrt.py",
        "Reinstalar modelos RIFE",
        "Regenerar TODO",
        "Volver"
    )
    $choice = Show-Menu -Title "¿Qué reparar?" -Options $items

    $profile = Get-GPUProfile -ProfileKey $gpuEnv.ProfileKey -ProfilesPath (Join-Path $wizardRoot "profiles\gpu-profiles.json")
    $backendType = switch ($gpuEnv.SupportedBackend) {
        "RIFE_TRT"  { "TRT" }
        "RIFE_NCNN" { "NCNN_VK" }
        default     { "MVTOOLS" }
    }

    switch ($choice) {
        0 {
            New-InterpolationVpy -BackendType $backendType -Profile $profile -Config $config `
                -DestDir $config.MpvConfigDir -Force -WizardVersion $Global:WizardVersion `
                -VpyTemplateVersion $Global:VpyTemplateVersion
        }
        1 {
            $concurrent = if ($profile.streams -eq 1) { 1 } else { 4 }
            New-AutoModeLua -Config $config -DestDir $config.MpvConfigDir -Force `
                -Buffered 8 -Concurrent $concurrent `
                -WizardVersion $Global:WizardVersion -LuaTemplateVersion $Global:LuaTemplateVersion
        }
        2 {
            $vsDir = Join-Path $config.BaseDir "vapoursynth-portable"
            $vsmlrtPy = Join-Path $vsDir "Lib\site-packages\vsmlrt.py"
            if (Test-Path $vsmlrtPy) {
                Invoke-VsmlrtPatch -Path $vsmlrtPy
            } else {
                Write-Bad "vsmlrt.py no encontrado"
            }
        }
        3 {
            $vsDir = Join-Path $config.BaseDir "vapoursynth-portable"
            $modelsToInstall = @($profile.model, "v4.25")
            Install-RIFEModels -Config $config -VsDir $vsDir -Models $modelsToInstall
        }
        4 {
            # Regenerate everything
            New-InterpolationVpy -BackendType $backendType -Profile $profile -Config $config `
                -DestDir $config.MpvConfigDir -Force -WizardVersion $Global:WizardVersion `
                -VpyTemplateVersion $Global:VpyTemplateVersion
            $concurrent = if ($profile.streams -eq 1) { 1 } else { 4 }
            New-AutoModeLua -Config $config -DestDir $config.MpvConfigDir -Force `
                -Buffered 8 -Concurrent $concurrent `
                -WizardVersion $Global:WizardVersion -LuaTemplateVersion $Global:LuaTemplateVersion
            New-SetDisplayHz -Config $config -DestDir $config.MpvConfigDir -Force `
                -WizardVersion $Global:WizardVersion -SetHzTemplateVersion $Global:SetHzTemplateVersion

            $vsDir = Join-Path $config.BaseDir "vapoursynth-portable"
            $vsmlrtPy = Join-Path $vsDir "Lib\site-packages\vsmlrt.py"
            if (Test-Path $vsmlrtPy) { Invoke-VsmlrtPatch -Path $vsmlrtPy }
        }
        5 { return }
        default { return }
    }
    Wait-Continue
}

# =============================================================================
# UPDATE FLOW
# =============================================================================
function Invoke-Update {
    Clear-Host
    Write-Title "ACTUALIZAR"
    $updates = Test-Updates -CurrentWizardVersion $Global:WizardVersion -Config $config

    if ($updates.Count -gt 0) {
        Write-Host ""
        foreach ($u in $updates) {
            Write-Host "  • $($u.Component): $($u.Current) → $($u.Latest)" -ForegroundColor Yellow
            Write-Host "    $($u.Url)" -ForegroundColor DarkGray
        }
    }
    Wait-Continue
}

# =============================================================================
# CONFIG FLOW
# =============================================================================
function Invoke-Config {
    Clear-Host
    Write-Title "CONFIGURACIÓN"

    Write-Host "  Configuración actual:" -ForegroundColor Cyan
    Write-Host "    mpv.exe      : $($config.MpvExe)" -ForegroundColor Gray
    Write-Host "    Config dir   : $($config.MpvConfigDir)" -ForegroundColor Gray
    Write-Host "    BaseDir      : $($config.BaseDir)" -ForegroundColor Gray
    Write-Host "    Local bundle : $($config.LocalBundleDir)" -ForegroundColor Gray
    Write-Host "    RIFE modelo  : $($config.RifeModel)" -ForegroundColor Gray
    Write-Host "    RIFE fp16    : $($config.RifeFp16)" -ForegroundColor Gray
    Write-Host "    RIFE streams : $($config.RifeStreams)" -ForegroundColor Gray
    Write-Host "    HDR interp   : $($config.HdrInterpolation)" -ForegroundColor Gray
    Write-Host "    Perfil       : $($config.QualityProfile)" -ForegroundColor Gray
    Write-Host ""

    $items = @(
        "Cambiar ruta de mpv.exe",
        "Cambiar carpeta config",
        "Cambiar BaseDir",
        "Toggle HDR interpolación (actualmente: $(if ($config.HdrInterpolation) { 'ON' } else { 'OFF' }))",
        "Cambiar perfil de calidad",
        "Volver"
    )
    $choice = Show-Menu -Title "¿Qué modificar?" -Options $items

    switch ($choice) {
        0 { $config.MpvExe = Read-PathPrompt -Label "Ruta a mpv.exe" -Default $config.MpvExe -MustExist $true }
        1 { $config.MpvConfigDir = Read-PathPrompt -Label "Carpeta config" -Default $config.MpvConfigDir -MustExist $false }
        2 { $config.BaseDir = Read-PathPrompt -Label "BaseDir" -Default $config.BaseDir -MustExist $false }
        3 {
            $config.HdrInterpolation = -not $config.HdrInterpolation
            Write-Ok "HDR interpolación: $(if ($config.HdrInterpolation) { 'ON' } else { 'OFF (Hz switch)' })"
        }
        4 {
            $profiles = @("Automático (según GPU)", "Máxima Calidad", "Balanceado", "Rendimiento", "Compatibilidad (MVTools)")
            $pc = Show-Menu -Title "Perfil de calidad" -Options $profiles
            switch ($pc) {
                0 { $config.QualityProfile = ""; $config.RifeModel = ""; $config.RifeFp16 = $null; $config.RifeStreams = $null }
                1 { $config.QualityProfile = "MaxQuality"; $config.RifeModel = "v4.25_heavy"; $config.RifeFp16 = $true; $config.RifeStreams = 2 }
                2 { $config.QualityProfile = "Balanced"; $config.RifeModel = "v4.25"; $config.RifeFp16 = $true; $config.RifeStreams = 2 }
                3 { $config.QualityProfile = "Performance"; $config.RifeModel = "v4.22"; $config.RifeFp16 = $true; $config.RifeStreams = 1 }
                4 { $config.QualityProfile = "Compat" }
            }
        }
        5 { return }
        default { return }
    }
    Export-WizardConfig -Config $config -Path $configPath | Out-Null
    Write-Ok "Configuración guardada"
    Wait-Continue
}

# =============================================================================
# UNINSTALL FLOW
# =============================================================================
function Invoke-Uninstall {
    Clear-Host
    Write-Title "DESINSTALAR"
    Write-Host "  Esto eliminará:" -ForegroundColor Yellow
    Write-Host "    • interpolation.vpy" -ForegroundColor Gray
    Write-Host "    • auto_mode.lua" -ForegroundColor Gray
    Write-Host "    • set_display_hz.ps1" -ForegroundColor Gray
    Write-Host "    • VapourSynth portable + vs-mlrt + modelos" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  NO elimina: mpv.exe, mpv.conf, ni otros archivos." -ForegroundColor DarkGray
    Write-Host ""
    $confirm = Read-Host "  ¿Continuar? (escribir 'DESINSTALAR' para confirmar)"
    if ($confirm -ne "DESINSTALAR") {
        Write-Info "Cancelado"
        Wait-Continue
        return
    }

    # Remove config files
    foreach ($f in @(
        (Join-Path $config.MpvConfigDir "interpolation.vpy"),
        (Join-Path $config.MpvConfigDir 'scripts\auto_mode.lua'),
        (Join-Path $config.MpvConfigDir "set_display_hz.ps1")
    )) {
        if (Test-Path $f) {
            Remove-Item $f -Force
            Write-Info "Eliminado: $f"
        }
    }

    # Remove VapourSynth directory
    $vsDir = Join-Path $config.BaseDir "vapoursynth-portable"
    if (Test-Path $vsDir) {
        Write-Info "Eliminando VapourSynth + vs-mlrt..."
        Remove-Item $vsDir -Recurse -Force
        Write-Ok "VapourSynth eliminado"
    }

    Write-Ok "Desinstalación completa"
    Wait-Continue
}

# =============================================================================
# MAIN LOOP
# =============================================================================

# Load or create config
$configPath = Get-ConfigFilePath
$config     = Import-WizardConfig -Path $configPath
$firstRun   = -not (Test-Path $configPath)

# Detect GPU once
$gpuEnv = Detect-GPU

# Welcome + first-time setup
if ($firstRun) {
    Show-Welcome
    Invoke-FirstTimeSetup
}

# Validate config
$configIssues = Test-WizardConfig -Config $config
if ($configIssues.Count -gt 0 -and -not $firstRun) {
    Write-Warn "Problemas en la configuración:"
    foreach ($issue in $configIssues) { Write-Warn "  • $issue" }
    Write-Host ""
    Invoke-FirstTimeSetup
}

# Check for updates (async-ish, non-blocking)
$updateFooter = ""
try {
    $updates = Test-Updates -CurrentWizardVersion $Global:WizardVersion -Config $config
    $updateFooter = Show-UpdateNotifications -Updates $updates
} catch {}

# Main menu loop
while ($true) {
    Clear-Host

    $isInstalled = Invoke-QuickCheck -Config $config -GPUEnv $gpuEnv
    $statusLine = if ($isInstalled) { '[OK] Instalado y funcional' } else { '[!!] No instalado o incompleto' }
    $gpuLine    = $gpuEnv.GPU + ' -> ' + $gpuEnv.SupportedBackend

    $menuItems = @(
        $(if ($isInstalled) { 'Reinstalar' } else { 'Instalar' }),
        'Actualizar',
        'Reparar',
        'Diagnostico',
        'Configuracion',
        'Desinstalar',
        'Salir'
    )

    $footer = "Estado: $statusLine | GPU: $gpuLine"
    if ($updateFooter) { $footer += " | $updateFooter" }

    $choice = Show-Menu -Title "MPV Interpolation Wizard v$Global:WizardVersion" -Options $menuItems -Footer $footer

    switch ($choice) {
        0 { Invoke-Install }
        1 { Invoke-Update }
        2 { Invoke-Repair }
        3 { Invoke-Diagnostics -Config $config -GPUEnv $gpuEnv; Wait-Continue }
        4 { Invoke-Config }
        5 { Invoke-Uninstall }
        6 { exit 0 }
        -1 { exit 0 }
    }
}
