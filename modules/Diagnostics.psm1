# =============================================================================
#  Diagnostics.psm1 - Deep diagnostic checks for the interpolation pipeline
# =============================================================================

function Invoke-Diagnostics {
    param(
        [hashtable]$Config,
        [hashtable]$GPUEnv
    )

    $results = [ordered]@{}
    $issues  = @()

    Write-Host ""
    Write-Host "  DIAGNOSTICO COMPLETO" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ""

    # 1) mpv.exe
    Write-Host "  [1/8] mpv.exe" -ForegroundColor Cyan
    if ($Config.MpvExe -and (Test-Path $Config.MpvExe)) {
        $hasVs = Test-MpvVapourSynth -MpvExe $Config.MpvExe
        $results['mpv.exe'] = @{ Status = 'OK'; Path = $Config.MpvExe; VapourSynth = $hasVs }
        Write-Host "     OK: $($Config.MpvExe)" -ForegroundColor Green
        if ($hasVs) {
            Write-Host '     OK: Soporte VapourSynth detectado' -ForegroundColor Green
        } else {
            Write-Host '     FAIL: SIN soporte VapourSynth' -ForegroundColor Red
            $issues += 'Tu mpv.exe no tiene soporte VapourSynth. Descarga un build de shinchiro o Gresaca.'
        }
    } else {
        $results['mpv.exe'] = @{ Status = 'MISSING' }
        Write-Host '     FAIL: No encontrado' -ForegroundColor Red
        $issues += ('mpv.exe no encontrado en: ' + $Config.MpvExe)
    }

    # 2) GPU
    Write-Host "  [2/8] GPU" -ForegroundColor Cyan
    $results['GPU'] = $GPUEnv
    Write-Host ('     GPU: ' + $GPUEnv.GPU) -ForegroundColor Gray
    Write-Host ('     Backend: ' + $GPUEnv.SupportedBackend) -ForegroundColor Gray
    Write-Host ('     Perfil: ' + $GPUEnv.ProfileKey) -ForegroundColor Gray

    # 3) VapourSynth
    Write-Host "  [3/8] VapourSynth" -ForegroundColor Cyan
    $vsStatus = Test-VapourSynthInstall -BaseDir $Config.BaseDir
    $results['VapourSynth'] = $vsStatus
    if ($vsStatus.Installed) {
        Write-Host ('     OK: Instalado (' + $vsStatus.Version + ')') -ForegroundColor Green
    } else {
        Write-Host '     FAIL: No instalado' -ForegroundColor Red
        $issues += 'VapourSynth no esta instalado. Ejecuta Instalar desde el menu.'
    }

    # 4) vs-mlrt
    Write-Host "  [4/8] vs-mlrt" -ForegroundColor Cyan
    if ($vsStatus.Installed) {
        $mlrtStatus = Test-VsMlrtInstall -VsDir $vsStatus.Path
        $results['vs-mlrt'] = $mlrtStatus
        if ($mlrtStatus.Installed) {
            $backendList = if ($mlrtStatus.Backends -and $mlrtStatus.Backends.Count -gt 0) {
                ' (' + ($mlrtStatus.Backends -join ', ') + ')'
            } else { '' }
            Write-Host ('     OK: Instalado' + $backendList) -ForegroundColor Green
            if ($mlrtStatus.TrtExec) { Write-Host '     OK: trtexec.exe presente' -ForegroundColor Green }
        } else {
            Write-Host '     FAIL: No instalado' -ForegroundColor Red
            $issues += 'vs-mlrt no esta instalado.'
        }

        # 5) vsmlrt.py patches
        Write-Host "  [5/8] Parches vsmlrt.py" -ForegroundColor Cyan
        if ($mlrtStatus.VsmlrtPy) {
            if ($mlrtStatus.VsmlrtPatched) {
                Write-Host '     OK: Parcheado correctamente' -ForegroundColor Green
            } else {
                Write-Host '     WARN: Sin parchear' -ForegroundColor Yellow
                $issues += 'vsmlrt.py necesita parches. Ejecuta Reparar desde el menu.'
            }
        } else {
            Write-Host '     FAIL: vsmlrt.py no encontrado' -ForegroundColor Red
            $issues += 'vsmlrt.py no encontrado - reinstalar vs-mlrt.'
        }

        # 6) Models
        Write-Host "  [6/8] Modelos RIFE" -ForegroundColor Cyan
        if ($mlrtStatus.ModelCount -gt 0) {
            Write-Host ('     OK: ' + $mlrtStatus.ModelCount + ' modelos ONNX') -ForegroundColor Green
        } else {
            Write-Host '     FAIL: Sin modelos' -ForegroundColor Red
            $issues += 'No hay modelos RIFE instalados.'
        }
    } else {
        Write-Host '  [4/8] vs-mlrt - (requiere VapourSynth)' -ForegroundColor DarkGray
        Write-Host '  [5/8] Parches - (requiere VapourSynth)' -ForegroundColor DarkGray
        Write-Host '  [6/8] Modelos - (requiere VapourSynth)' -ForegroundColor DarkGray
    }

    # 6b) Persistent env vars left by older install scripts
    #     Old install_interp-2.ps1 used to call setx/SetEnvironmentVariable for
    #     VSSCRIPT_PATH and PYTHONPATH at User scope, often pointing to a
    #     directory (or a non-existent DLL path). mpv reads VSSCRIPT_PATH on
    #     Windows and does LoadLibrary() on it directly, so a bad value makes
    #     every direct mpv.exe launch fail with 0x7e even when mpv-vs.bat would
    #     have worked. Detect and offer to clean up.
    Write-Host '  [extra] Variables de entorno persistentes' -ForegroundColor Cyan
    $envIssues = Get-StaleVsEnvVars
    if ($envIssues.Count -eq 0) {
        Write-Host '     OK: Variables de entorno limpias (sin PYTHONHOME/PYTHONPATH globales)' -ForegroundColor Green
    } else {
        foreach ($e in $envIssues) {
            Write-Host ('     WARN: ' + $e.Name + ' (' + $e.Scope + ') = ' + $e.Value) -ForegroundColor Yellow
            Write-Host ('            ' + $e.Reason) -ForegroundColor DarkGray
        }
        $issues += 'Variables de entorno persistentes mal configuradas. Ejecuta Reparar para limpiarlas.'
    }

    # 7) FRUC Vulkan availability
    Write-Host '  [7/8] FRUC Vulkan' -ForegroundColor Cyan
    $activeBackend = if ($Config.ActiveBackend) { $Config.ActiveBackend } else { 'auto' }
    Write-Host ('     Backend activo: ' + $activeBackend) -ForegroundColor Gray
    if ($GPUEnv.FrucEligible) {
        $frucOk = Test-FrucVulkanAvailable -MpvExe $Config.MpvExe
        $results['FRUC'] = @{ Eligible = $true; Available = $frucOk }
        if ($frucOk) {
            Write-Host '     OK: fruc_vulkan disponible en este build de mpv' -ForegroundColor Green
        } else {
            Write-Host '     INFO: fruc_vulkan no disponible (build de mpv no lo incluye aun)' -ForegroundColor Yellow
            if ($activeBackend -eq 'FRUC_VK') {
                $issues += 'FRUC Vulkan configurado como backend pero no disponible en este build de mpv.'
            }
        }
        $ffmpegVer = Get-MpvFFmpegVersion -MpvExe $Config.MpvExe
        if ($ffmpegVer) {
            Write-Host ('     FFmpeg: ' + $ffmpegVer) -ForegroundColor DarkGray
        }
    } else {
        $results['FRUC'] = @{ Eligible = $false; Available = $false }
        Write-Host '     N/A: GPU no soporta FRUC Vulkan (requiere RTX 30+)' -ForegroundColor DarkGray
    }

    # 8) mpv config files
    Write-Host '  [8/8] Archivos de config' -ForegroundColor Cyan
    $vpyPath = Join-Path $Config.MpvConfigDir 'interpolation.vpy'
    $luaPath = Join-Path $Config.MpvConfigDir 'scripts\auto_mode.lua'
    $hzPath  = Join-Path $Config.MpvConfigDir 'set_display_hz.ps1'

    $fileList = @(
        @{ Name = 'interpolation.vpy'; Path = $vpyPath },
        @{ Name = 'auto_mode.lua'; Path = $luaPath },
        @{ Name = 'set_display_hz.ps1'; Path = $hzPath }
    )
    foreach ($file in $fileList) {
        if (Test-Path $file.Path) {
            Write-Host ('     OK: ' + $file.Name) -ForegroundColor Green
            try {
                $first = Get-Content $file.Path -TotalCount 3 -EA SilentlyContinue
                $ver   = $first | Select-String -Pattern 'template-version:\s*(\d+)' | Select-Object -First 1
                if ($ver) {
                    Write-Host ('       Version template: ' + $ver.Matches[0].Groups[1].Value) -ForegroundColor DarkGray
                }
            } catch {}
        } else {
            # interpolation.vpy is not needed for FRUC-only installs
            if ($file.Name -eq 'interpolation.vpy' -and $activeBackend -eq 'FRUC_VK') {
                Write-Host ('     OK: ' + $file.Name + ' (no necesario — backend FRUC)') -ForegroundColor DarkGray
            } else {
                Write-Host ('     WARN: ' + $file.Name + ' no encontrado') -ForegroundColor Yellow
                $issues += ($file.Name + ' no existe en ' + $Config.MpvConfigDir)
            }
        }
    }

    # Summary
    Write-Host ''
    if ($issues.Count -eq 0) {
        Write-Host '  OK - interpolacion deberia funcionar' -ForegroundColor Green
    } else {
        Write-Host ('  ' + $issues.Count + ' problema(s) encontrado(s):') -ForegroundColor Red
        foreach ($issue in $issues) {
            Write-Host ('    - ' + $issue) -ForegroundColor Yellow
        }
    }
    Write-Host ''

    return @{
        Results = $results
        Issues  = $issues
        IsOk    = ($issues.Count -eq 0)
    }
}

function Get-StaleVsEnvVars {
    <#
    .SYNOPSIS
        Returns a list of persistent env vars (User/Machine scope) that are
        misconfigured or no longer needed.

        PYTHONHOME y PYTHONPATH a nivel User/Machine siempre se reportan como
        problema si apuntan a un VS portable: causan conflictos con otras
        instalaciones de Python del sistema, independientemente de si la ruta
        existe o no.
    .OUTPUTS
        Array of @{ Name; Scope; Value; Reason } — empty if everything is OK.
    #>
    param([string]$VsDir = $null)

    $bad = @()
    foreach ($scope in 'User','Machine') {
        # VSSCRIPT_PATH debe apuntar a la DLL vsscript.dll del install actual
        $vs = [System.Environment]::GetEnvironmentVariable('VSSCRIPT_PATH', $scope)
        if ($vs) {
            $reason = $null
            if (-not (Test-Path $vs)) {
                $reason = 'Apunta a una ruta inexistente'
            } elseif ((Get-Item $vs -EA SilentlyContinue).PSIsContainer) {
                $reason = 'Apunta a un directorio (mpv espera la DLL completa)'
            } elseif ($VsDir -and -not $vs.ToLower().StartsWith($VsDir.ToLower())) {
                $reason = "Apunta a otro install (esperado bajo $VsDir)"
            }
            if ($reason) {
                $bad += @{ Name = 'VSSCRIPT_PATH'; Scope = $scope; Value = $vs; Reason = $reason }
            }
        }
        # PYTHONPATH apuntando a VS portable SIEMPRE es problema:
        # rompe otras instalaciones de Python del sistema.
        $pp = [System.Environment]::GetEnvironmentVariable('PYTHONPATH', $scope)
        if ($pp -and $pp -match 'vapoursynth') {
            $bad += @{
                Name   = 'PYTHONPATH'
                Scope  = $scope
                Value  = $pp
                Reason = 'PYTHONPATH global apuntando a VS portable rompe otras instalaciones de Python. Debe eliminarse.'
            }
        }
        # PYTHONHOME apuntando a VS portable SIEMPRE es problema:
        # rompe otras instalaciones de Python del sistema.
        $ph = [System.Environment]::GetEnvironmentVariable('PYTHONHOME', $scope)
        if ($ph -and $ph -match 'vapoursynth') {
            $bad += @{
                Name   = 'PYTHONHOME'
                Scope  = $scope
                Value  = $ph
                Reason = 'PYTHONHOME global apuntando a VS portable rompe otras instalaciones de Python. Debe eliminarse.'
            }
        }
    }
    return ,$bad
}

function Set-WizardVsEnvVars {
    <#
    .SYNOPSIS
        Setea las env vars de VapourSynth a nivel User para que mpv.exe directo
        las herede al lanzarse (no requiere mpv-vs.bat para cada launch).

        IMPORTANTE: NO se setean PYTHONHOME ni PYTHONPATH de forma persistente
        porque romperian otras instalaciones de Python del sistema. En su lugar
        se usa solo VSSCRIPT_PATH + se extiende PATH con los directorios de VS.

        Esto deja persistente lo que mpv-vs.bat hace por sesion. Despues de
        setear, hay que cerrar sesion / reiniciar para que Explorer (y los
        terminales hijos) las pickeen.
    #>
    param(
        [Parameter(Mandatory)][string]$VsDir
    )
    if (-not (Test-Path $VsDir)) {
        Write-Warning "VsDir no existe: $VsDir"
        return $false
    }

    # --- VSSCRIPT_PATH: DLL que mpv carga directamente para VapourSynth ---
    $vsScriptDll = Join-Path $VsDir "Lib\site-packages\vapoursynth\vsscript.dll"
    if (-not (Test-Path $vsScriptDll)) { $vsScriptDll = Join-Path $VsDir "vsscript.dll" }
    [System.Environment]::SetEnvironmentVariable('VSSCRIPT_PATH', $vsScriptDll, 'User')
    Write-Host ("     VSSCRIPT_PATH = $vsScriptDll") -ForegroundColor DarkGray

    # --- VAPOURSYNTH_EXTRA_PLUGIN_PATH ---
    $pluginPath = Join-Path $VsDir "vs-plugins"
    [System.Environment]::SetEnvironmentVariable('VAPOURSYNTH_EXTRA_PLUGIN_PATH', $pluginPath, 'User')
    Write-Host ("     VAPOURSYNTH_EXTRA_PLUGIN_PATH = $pluginPath") -ForegroundColor DarkGray

    # --- Limpiar PYTHONHOME y PYTHONPATH si el wizard los habia seteado antes ---
    # (versiones anteriores del wizard los seteaban, lo que rompe otras instalaciones
    # de Python. Los eliminamos de User scope si apuntan a este VS portable.)
    foreach ($varName in @('PYTHONHOME','PYTHONPATH')) {
        $cur = [System.Environment]::GetEnvironmentVariable($varName, 'User')
        if ($cur -and $cur.ToLower().StartsWith($VsDir.ToLower())) {
            [System.Environment]::SetEnvironmentVariable($varName, $null, 'User')
            Write-Host ("     [limpiado] $varName (ya no se necesita a nivel sistema)") -ForegroundColor Yellow
        }
    }

    # --- PATH: agregar VS dirs para que python313.dll y DLLs de CUDA se carguen ---
    $cudaDir  = Join-Path $VsDir "vs-plugins\vsmlrt-cuda"
    $vsDirs   = @($VsDir, (Join-Path $VsDir "Lib\site-packages"), $cudaDir)
    $curPath  = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if (-not $curPath) { $curPath = '' }
    $pathParts = $curPath -split ';' | Where-Object { $_ -ne '' }

    $added = @()
    foreach ($d in $vsDirs) {
        if ($pathParts -notcontains $d) {
            $pathParts = @($d) + $pathParts
            $added += $d
        }
    }
    if ($added.Count -gt 0) {
        [System.Environment]::SetEnvironmentVariable('PATH', ($pathParts -join ';'), 'User')
        foreach ($d in $added) {
            Write-Host ("     PATH += $d") -ForegroundColor DarkGray
        }
    } else {
        Write-Host '     PATH ya contiene los directorios de VS' -ForegroundColor DarkGray
    }

    Write-Host "[OK] Env vars seteadas a nivel User (sin PYTHONHOME/PYTHONPATH)" -ForegroundColor Green
    Write-Host "     Cierra sesion / reinicia para que Explorer las pickee." -ForegroundColor Yellow
    return $true
}

function Clear-StaleVsEnvVars {
    <#
    .SYNOPSIS
        Removes the persistent env vars flagged by Get-StaleVsEnvVars.
    #>
    $cleared = @()
    foreach ($e in (Get-StaleVsEnvVars)) {
        [System.Environment]::SetEnvironmentVariable($e.Name, $null, $e.Scope)
        $cleared += "$($e.Name) ($($e.Scope))"
    }
    return $cleared
}

function Invoke-QuickCheck {
    param([hashtable]$Config, [hashtable]$GPUEnv)

    if (-not $Config.MpvExe -or -not (Test-Path $Config.MpvExe)) { return $false }

    $vsDir = Join-Path $Config.BaseDir 'vapoursynth-portable'
    $vspipe = Join-Path $vsDir 'VSPipe.exe'
    if (-not (Test-Path $vspipe)) { $vspipe = Join-Path $vsDir 'Scripts\vspipe.exe' }
    if (-not (Test-Path $vspipe)) { return $false }

    $vpyPath = Join-Path $Config.MpvConfigDir 'interpolation.vpy'
    if (-not (Test-Path $vpyPath)) { return $false }

    $luaPath = Join-Path $Config.MpvConfigDir 'scripts\auto_mode.lua'
    if (-not (Test-Path $luaPath)) { return $false }

    return $true
}

Export-ModuleMember -Function Invoke-Diagnostics, Invoke-QuickCheck, `
    Get-StaleVsEnvVars, Clear-StaleVsEnvVars, Set-WizardVsEnvVars
