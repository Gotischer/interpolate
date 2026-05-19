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
            Write-Host '     OK: Instalado' -ForegroundColor Green
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

function Invoke-QuickCheck {
    param([hashtable]$Config, [hashtable]$GPUEnv)

    if (-not $Config.MpvExe -or -not (Test-Path $Config.MpvExe)) { return $false }

    $vsDir = Join-Path $Config.BaseDir 'vapoursynth-portable'
    if (-not (Test-Path (Join-Path $vsDir 'VSPipe.exe'))) { return $false }

    $vpyPath = Join-Path $Config.MpvConfigDir 'interpolation.vpy'
    if (-not (Test-Path $vpyPath)) { return $false }

    $luaPath = Join-Path $Config.MpvConfigDir 'scripts\auto_mode.lua'
    if (-not (Test-Path $luaPath)) { return $false }

    return $true
}

Export-ModuleMember -Function Invoke-Diagnostics, Invoke-QuickCheck
