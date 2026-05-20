# =============================================================================
#  Templates.psm1 — Generate configuration files from templates
#
#  Reads template files with {{PLACEHOLDER}} markers and substitutes values
#  from the wizard configuration. No Python-in-PowerShell escaping issues.
# =============================================================================

function Get-TemplatesDir {
    # Templates are in the templates/ directory relative to the wizard root
    $moduleDir = Split-Path $PSScriptRoot -Parent
    $tplDir    = Join-Path $moduleDir "templates"
    if (Test-Path $tplDir) { return $tplDir }
    # When running from .bat, templates may be alongside the script
    return $PSScriptRoot
}

function Build-BackendExpression {
    <#
    .SYNOPSIS
        Builds the Python Backend expression string for the RIFE template.
    #>
    param(
        [string]$BackendType,
        [string]$Fp16Str,
        [int]$Streams,
        [int]$Workspace = 0,
        [string]$GPUGen = ""
    )

    $wsParam = if ($Workspace -gt 0) { ", workspace=$Workspace" } else { "" }

    switch ($BackendType) {
        "TRT" {
            return "Backend.TRT(fp16=$Fp16Str, num_streams=$Streams, device_id=0$wsParam)"
        }
        "TRT_RTX" {
            return "Backend.TRT_RTX(fp16=$Fp16Str, num_streams=$Streams, device_id=0$wsParam)"
        }
        "NCNN_VK" {
            return "Backend.NCNN_VK(fp16=$Fp16Str, num_streams=$Streams, device_id=0)"
        }
        default {
            return "Backend.TRT(fp16=$Fp16Str, num_streams=$Streams, device_id=0$wsParam)"
        }
    }
}

function New-InterpolationVpy {
    <#
    .SYNOPSIS
        Generates interpolation.vpy from the RIFE or MVTools template.
    .PARAMETER BackendType
        "TRT", "TRT_RTX", "NCNN_VK", or "MVTOOLS"
    .PARAMETER Profile
        GPU profile object from gpu-profiles.json
    .PARAMETER Config
        Wizard config hashtable
    .PARAMETER DestDir
        Directory to write interpolation.vpy (typically MpvConfigDir)
    .PARAMETER Force
        Overwrite existing file
    #>
    param(
        [string]$BackendType = "TRT",
        [PSCustomObject]$Profile,
        [hashtable]$Config,
        [string]$DestDir,
        [switch]$Force,
        [string]$WizardVersion = "2.0.0",
        [int]$VpyTemplateVersion = 1
    )

    Write-Host "`n===> Generando interpolation.vpy" -ForegroundColor Cyan

    $dst    = Join-Path $DestDir "interpolation.vpy"
    $parent = Split-Path $dst -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    # Backup existing
    if ((Test-Path $dst) -and -not $Force) {
        Write-Host "     Ya existe (usa -Force o Reparar para regenerar)" -ForegroundColor Gray
        return $dst
    }
    if (Test-Path $dst) {
        $bak = "$dst.bak"
        Copy-Item $dst $bak -Force
        Write-Host "     Backup → $bak" -ForegroundColor DarkGray
    }

    # Determine template
    $tplDir = Get-TemplatesDir
    if ($BackendType -eq "MVTOOLS") {
        $tplFile = Join-Path $tplDir "interpolation-mvtools.vpy"
    } else {
        $tplFile = Join-Path $tplDir "interpolation-rife.vpy"
    }

    if (-not (Test-Path $tplFile)) {
        throw "Template not found: $tplFile"
    }

    $content = Get-Content $tplFile -Raw -Encoding UTF8

    if ($BackendType -ne "MVTOOLS") {
        # Resolve RIFE parameters from config (override) or profile (default)
        $model   = if ($Config.RifeModel)   { $Config.RifeModel }   elseif ($Profile.model)   { $Profile.model }   else { "v4.25" }
        $fp16    = if ($null -ne $Config.RifeFp16) { $Config.RifeFp16 } elseif ($null -ne $Profile.fp16) { $Profile.fp16 } else { $true }
        $streams = if ($Config.RifeStreams)  { $Config.RifeStreams }  elseif ($Profile.streams) { $Profile.streams } else { 2 }
        $ws      = if ($Profile.workspace)  { [int]$Profile.workspace } else { 0 }
        $hdrInterp = if ($null -ne $Config.HdrInterpolation) { $Config.HdrInterpolation } else { $true }

        # Build enum string: "v4.25_heavy" -> "RIFEModel.v4_25_heavy"
        $modelEnum = "RIFEModel." + ($model -replace '\.', '_')
        $fp16Str   = if ($fp16) { "True" } else { "False" }
        $hdrStr    = if ($hdrInterp) { "True" } else { "False" }

        $backendExpr = Build-BackendExpression -BackendType $BackendType `
            -Fp16Str $fp16Str -Streams $streams -Workspace $ws -GPUGen ""

        # Substitute placeholders
        $content = $content -replace '{{VPY_TEMPLATE_VERSION}}', $VpyTemplateVersion
        $content = $content -replace '{{WIZARD_VERSION}}', $WizardVersion
        $content = $content -replace '{{BACKEND_TYPE}}', $BackendType
        $content = $content -replace '{{RIFE_MODEL}}', $model
        $content = $content -replace '{{RIFE_MODEL_ENUM}}', $modelEnum
        $content = $content -replace '{{NUM_STREAMS}}', $streams
        $content = $content -replace '{{FP16}}', $fp16Str
        $content = $content -replace '{{HDR_INTERPOLATION}}', $hdrStr
        $content = $content -replace '{{BACKEND_EXPR}}', $backendExpr
    } else {
        # MVTools template - simpler substitutions
        $content = $content -replace '{{VPY_TEMPLATE_VERSION}}', $VpyTemplateVersion
        $content = $content -replace '{{WIZARD_VERSION}}', $WizardVersion
    }

    Set-Content $dst $content -Encoding UTF8
    Write-Host "[OK] interpolation.vpy creado en $dst" -ForegroundColor Green
    Write-Host "     Backend: $BackendType" -ForegroundColor DarkGray
    if ($BackendType -ne "MVTOOLS") {
        Write-Host "     Modelo: $model | fp16: $fp16Str | streams: $streams" -ForegroundColor DarkGray
    }
    return $dst
}

function New-AutoModeLua {
    <#
    .SYNOPSIS
        Generates auto_mode.lua from the template.
    #>
    param(
        [hashtable]$Config,
        [string]$DestDir,
        [switch]$Force,
        [int]$Buffered = 8,
        [int]$Concurrent = 4,
        [string]$WizardVersion = "2.0.0",
        [int]$LuaTemplateVersion = 1
    )

    Write-Host "`n===> Generando auto_mode.lua" -ForegroundColor Cyan

    $scriptsDir = Join-Path $DestDir "scripts"
    if (-not (Test-Path $scriptsDir)) { New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null }
    $dst = Join-Path $scriptsDir "auto_mode.lua"

    if ((Test-Path $dst) -and -not $Force) {
        Write-Host "     Ya existe (usa -Force o Reparar para regenerar)" -ForegroundColor Gray
        return $dst
    }
    if (Test-Path $dst) {
        # Backup outside scripts/ (mpv tries to load .bak files)
        $bakDir = Join-Path $DestDir "wizard-backups"
        if (-not (Test-Path $bakDir)) { New-Item -ItemType Directory -Path $bakDir | Out-Null }
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $bak   = Join-Path $bakDir "auto_mode.lua.$stamp.bak"
        Copy-Item $dst $bak -Force
        Write-Host "     Backup → $bak" -ForegroundColor DarkGray
    }

    $tplDir  = Get-TemplatesDir
    $tplFile = Join-Path $tplDir "auto_mode.lua"
    if (-not (Test-Path $tplFile)) { throw "Template not found: $tplFile" }

    $content = Get-Content $tplFile -Raw -Encoding UTF8

    $hdrInterp = if ($null -ne $Config.HdrInterpolation -and $Config.HdrInterpolation) { "true" } else { "false" }

    $content = $content -replace '{{LUA_TEMPLATE_VERSION}}', $LuaTemplateVersion
    $content = $content -replace '{{WIZARD_VERSION}}', $WizardVersion
    $content = $content -replace '{{BUFFERED_FRAMES}}', $Buffered
    $content = $content -replace '{{CONCURRENT_FRAMES}}', $Concurrent
    $content = $content -replace '{{HDR_INTERPOLATION}}', $hdrInterp

    Set-Content $dst $content -Encoding UTF8
    Write-Host "[OK] auto_mode.lua creado" -ForegroundColor Green
    return $dst
}

function New-SetDisplayHz {
    <#
    .SYNOPSIS
        Generates set_display_hz.ps1 from the template.
    #>
    param(
        [hashtable]$Config,
        [string]$DestDir,
        [switch]$Force,
        [string]$WizardVersion = "2.0.0",
        [int]$SetHzTemplateVersion = 1
    )

    $dst = Join-Path $DestDir "set_display_hz.ps1"
    if ((Test-Path $dst) -and -not $Force) {
        Write-Host "     set_display_hz.ps1 ya existe" -ForegroundColor Gray
        return $dst
    }

    $tplDir  = Get-TemplatesDir
    $tplFile = Join-Path $tplDir "set_display_hz.ps1"
    if (-not (Test-Path $tplFile)) { throw "Template not found: $tplFile" }

    $content = Get-Content $tplFile -Raw -Encoding UTF8
    $display = if ($Config.DisplayDevice) { $Config.DisplayDevice } else { "" }

    $content = $content -replace '{{SETHZ_TEMPLATE_VERSION}}', $SetHzTemplateVersion
    $content = $content -replace '{{WIZARD_VERSION}}', $WizardVersion
    $content = $content -replace '{{DISPLAY_DEVICE}}', $display

    Set-Content $dst $content -Encoding UTF8
    Write-Host "[OK] set_display_hz.ps1 creado" -ForegroundColor Green
    return $dst
}

function New-MpvLauncher {
    <#
    .SYNOPSIS
        Generates mpv-vs.bat that sets VapourSynth environment variables before launching mpv.
    .DESCRIPTION
        mpv uses SetDefaultDllDirectories which restricts DLL search to the app directory
        and System32. To load VapourSynth's VSScript.dll (and its Python dependencies),
        we must set VSSCRIPT_PATH to the full DLL path and add the VS portable directory
        to PATH so that python313.dll and other dependencies are found.
    #>
    param(
        [hashtable]$Config,
        [switch]$Force
    )

    $mpvExe = $Config.MpvExe
    if (-not $mpvExe) { Write-Warning "MpvExe no configurado, omitiendo launcher"; return $null }

    $mpvDir = Split-Path $mpvExe -Parent
    $dst    = Join-Path $mpvDir "mpv-vs.bat"

    if ((Test-Path $dst) -and -not $Force) {
        Write-Host "     mpv-vs.bat ya existe" -ForegroundColor Gray
        return $dst
    }

    # Locate VapourSynth portable directory
    $vsDir = Join-Path $Config.BaseDir "vapoursynth-portable"
    if (-not (Test-Path $vsDir)) {
        Write-Warning "VapourSynth portable no encontrado en $vsDir, omitiendo launcher"
        return $null
    }

    $vsScriptDll = Join-Path $vsDir "Lib\site-packages\vapoursynth\vsscript.dll"
    if (-not (Test-Path $vsScriptDll)) {
        $vsScriptDll = Join-Path $vsDir "vsscript.dll"
    }
    if (-not (Test-Path $vsScriptDll)) {
        $vsScriptDll = Join-Path $vsDir "VSScript.dll"
    }
    if (-not (Test-Path $vsScriptDll)) {
        Write-Warning "VSScript.dll / vsscript.dll no encontrado en $vsDir"
        return $null
    }

    Write-Host "`n===> Generando mpv-vs.bat (launcher con entorno VS)" -ForegroundColor Cyan

    $batContent = @"
@echo off
rem ========================================================================
rem  mpv-vs.bat - Launch mpv with VapourSynth environment configured
rem  Generated by mpv-interp-wizard. Use this instead of mpv.exe directly.
rem ========================================================================
set VSSCRIPT_PATH=$vsScriptDll
set PYTHONHOME=$vsDir
set PYTHONPATH=$vsDir\Lib\site-packages
set VAPOURSYNTH_EXTRA_PLUGIN_PATH=$vsDir\vs-plugins
set PATH=$vsDir;$vsDir\Lib\site-packages;$vsDir\vs-plugins\vsmlrt-cuda;$vsDir\vs-plugins\vsort;$vsDir\vs-plugins\vsov;%PATH%

rem Launch mpv with all arguments forwarded
"$mpvExe" --player-operation-mode=pseudo-gui %*
"@

    Set-Content $dst $batContent -Encoding ASCII
    Write-Host "[OK] mpv-vs.bat creado en $dst" -ForegroundColor Green
    Write-Host "     Usa mpv-vs.bat en lugar de mpv.exe para interpolacion" -ForegroundColor DarkGray
    return $dst
}

Export-ModuleMember -Function New-InterpolationVpy, New-AutoModeLua, New-SetDisplayHz, `
    New-MpvLauncher, Build-BackendExpression, Get-TemplatesDir
