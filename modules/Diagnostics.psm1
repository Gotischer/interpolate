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
    Write-Host "  [1/7] mpv.exe" -ForegroundColor Cyan
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
    Write-Host "  [2/7] GPU" -ForegroundColor Cyan
    $results['GPU'] = $GPUEnv
    Write-Host ('     GPU: ' + $GPUEnv.GPU) -ForegroundColor Gray
    Write-Host ('     Backend: ' + $GPUEnv.SupportedBackend) -ForegroundColor Gray
    Write-Host ('     Perfil: ' + $GPUEnv.ProfileKey) -ForegroundColor Gray

    # 3) VapourSynth
    Write-Host "  [3/7] VapourSynth" -ForegroundColor Cyan
    $vsStatus = Test-VapourSynthInstall -BaseDir $Config.BaseDir
    $results['VapourSynth'] = $vsStatus
    if ($vsStatus.Installed) {
        Write-Host ('     OK: Instalado (' + $vsStatus.Version + ')') -ForegroundColor Green
    } else {
        Write-Host '     FAIL: No instalado' -ForegroundColor Red
        $issues += 'VapourSynth no esta instalado. Ejecuta Instalar desde el menu.'
    }

    # 4) vs-mlrt
    Write-Host "  [4/7] vs-mlrt" -ForegroundColor Cyan
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
        Write-Host "  [5/7] Parches vsmlrt.py" -ForegroundColor Cyan
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
        Write-Host "  [6/7] Modelos RIFE" -ForegroundColor Cyan
        if ($mlrtStatus.ModelCount -gt 0) {
            Write-Host ('     OK: ' + $mlrtStatus.ModelCount + ' modelos ONNX') -ForegroundColor Green
        } else {
            Write-Host '     FAIL: Sin modelos' -ForegroundColor Red
            $issues += 'No hay modelos RIFE instalados.'
        }
    } else {
        Write-Host '  [4/7] vs-mlrt - (requiere VapourSynth)' -ForegroundColor DarkGray
        Write-Host '  [5/7] Parches - (requiere VapourSynth)' -ForegroundColor DarkGray
        Write-Host '  [6/7] Modelos - (requiere VapourSynth)' -ForegroundColor DarkGray
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
        Write-Host '     OK: VSSCRIPT_PATH / PYTHONPATH limpios' -ForegroundColor Green
    } else {
        foreach ($e in $envIssues) {
            Write-Host ('     WARN: ' + $e.Name + ' (' + $e.Scope + ') = ' + $e.Value) -ForegroundColor Yellow
            Write-Host ('            ' + $e.Reason) -ForegroundColor DarkGray
        }
        $issues += 'Variables de entorno persistentes mal configuradas. Ejecuta Reparar para limpiarlas.'
    }

    # 7) mpv config files
    Write-Host '  [7/7] Archivos de config' -ForegroundColor Cyan
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
            Write-Host ('     WARN: ' + $file.Name + ' no encontrado') -ForegroundColor Yellow
            $issues += ($file.Name + ' no existe en ' + $Config.MpvConfigDir)
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
        Returns a list of persistent env vars (User/Machine scope) that look
        like leftovers from old install scripts and are known to break direct
        mpv.exe launches. Pure detection; does not modify the environment.
    .OUTPUTS
        Array of @{ Name; Scope; Value; Reason } — empty if everything is clean.
    #>
    $bad = @()
    foreach ($scope in 'User','Machine') {
        $vs = [System.Environment]::GetEnvironmentVariable('VSSCRIPT_PATH', $scope)
        if ($vs) {
            # Any persistent VSSCRIPT_PATH is suspect: the canonical setup uses
            # mpv-vs.bat which sets it per-session. A persistent value will
            # leak into every direct mpv.exe launch.
            $reason = if (-not (Test-Path $vs)) {
                'Apunta a una ruta inexistente'
            } elseif ((Get-Item $vs -EA SilentlyContinue).PSIsContainer) {
                'Apunta a un directorio (mpv espera la DLL completa)'
            } else {
                'Variable persistente: mejor dejar que mpv-vs.bat la configure por sesion'
            }
            $bad += @{ Name = 'VSSCRIPT_PATH'; Scope = $scope; Value = $vs; Reason = $reason }
        }
        $pp = [System.Environment]::GetEnvironmentVariable('PYTHONPATH', $scope)
        if ($pp -and $pp -match 'vapoursynth') {
            $bad += @{ Name = 'PYTHONPATH'; Scope = $scope; Value = $pp;
                       Reason = 'PYTHONPATH global apuntando a VS portable contamina otros Python instalados' }
        }
    }
    return ,$bad
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
    Get-StaleVsEnvVars, Clear-StaleVsEnvVars
