# =============================================================================
#  VapourSynth.psm1 — VapourSynth portable installation and management
#
#  Handles: download, extraction, and verification of VapourSynth R76+
#  portable distribution.
# =============================================================================

function Install-VapourSynth {
    <#
    .SYNOPSIS
        Downloads and installs VapourSynth portable into BaseDir/vapoursynth-portable.
    #>
    param(
        [hashtable]$Config,
        [string]$TargetRelease = "R76",
        [switch]$Force
    )
    $vsDir = Join-Path $Config.BaseDir "vapoursynth-portable"
    $vspipe = Join-Path $vsDir "VSPipe.exe"
    $pyExe = Join-Path $vsDir "python.exe"

    # Detect target version tag number
    $tagNum = 76
    if ($TargetRelease -match 'R?(\d+)') {
        $tagNum = [int]$Matches[1]
    }

    $alreadyInstalled = $false
    if (Test-Path $vspipe) {
        if ($tagNum -lt 74 -or (Test-Path $pyExe)) {
            $alreadyInstalled = $true
        }
    }

    if ($alreadyInstalled -and -not $Force) {
        Write-Host "[OK] VapourSynth ya instalado en $vsDir" -ForegroundColor Green
        return $vsDir
    }

    if ($Force -and (Test-Path $vsDir)) {
        Write-Host "     Limpiando archivos antiguos de VapourSynth..." -ForegroundColor Gray
        # Delete everything in $vsDir EXCEPT 'vs-plugins' and 'vs-coreplugins'
        Get-ChildItem $vsDir | Where-Object { $_.Name -notmatch '^vs-(plugins|coreplugins)$' } |
            Remove-Item -Recurse -Force -EA SilentlyContinue
    }

    Write-Host "`n===> Instalando VapourSynth $TargetRelease" -ForegroundColor Cyan

    # Get latest release info
    $repo = "vapoursynth/vapoursynth"
    $rel  = Get-LatestGithubRelease -Repo $repo

    if (-not $rel) {
        Write-Host "[!!] No se pudo obtener info de release, usando URL directa" -ForegroundColor Yellow
        $tag = $TargetRelease
    } else {
        $tag = $rel.Tag
        Write-Host "     Última versión: $tag" -ForegroundColor Gray
    }

    # Re-evaluate tag number based on actual tag from GitHub
    if ($tag -match 'R?(\d+)') {
        $tagNum = [int]$Matches[1]
    }

    # 1) If R74+, we must download and extract Python embedded first
    if ($tagNum -ge 74) {
        $pyVersion = "3.13.2"
        $pyZipName = "python-$pyVersion-embed-amd64.zip"
        $pyUrl = "https://www.python.org/ftp/python/$pyVersion/$pyZipName"

        Write-Host "     Descargando Python $pyVersion embedded..." -ForegroundColor Gray
        $pyZipPath = Invoke-Download -FileName $pyZipName -Url $pyUrl -BaseDir $Config.BaseDir `
            -LocalBundleDir $Config.LocalBundleDir

        Write-Host "     Extrayendo Python..." -ForegroundColor Gray
        if (-not (Test-Path $vsDir)) { New-Item -ItemType Directory -Path $vsDir | Out-Null }
        Expand-Archive -Path $pyZipPath -DestinationPath $vsDir -Force

        # Configure python313._pth to enable site-packages and site.py
        $pthFile = Join-Path $vsDir "python313._pth"
        if (Test-Path $pthFile) {
            Write-Host "     Configurando python313._pth..." -ForegroundColor Gray
            $pthContent = @"
python313.zip
.

# Uncomment to run site.main() automatically
import site
Lib\site-packages
"@
            Set-Content $pthFile $pthContent -Encoding ASCII
        }

        # Download get-pip.py
        $pipScript = Join-Path $Config.BaseDir "get-pip.py"
        if (-not (Test-Path $pipScript)) {
            Write-Host "     Descargando get-pip.py..." -ForegroundColor Gray
            Invoke-Download -FileName "get-pip.py" -Url "https://bootstrap.pypa.io/get-pip.py" -BaseDir $Config.BaseDir `
                -LocalBundleDir $Config.LocalBundleDir | Out-Null
        }

        # Install pip
        Write-Host "     Instalando pip..." -ForegroundColor Gray
        & $pyExe $pipScript --no-warn-script-location | Out-Host
    }

    # 2) Look for the portable zip in assets and download
    $zipName = "VapourSynth64-Portable-$tag.zip"
    $zipAsset = $null
    if ($rel -and $rel.Assets) {
        $zipAsset = $rel.Assets | Where-Object { $_.Name -like "*Portable*" -and $_.Name -like "*.zip" } |
                    Select-Object -First 1
    }

    $zipUrl = if ($zipAsset) { $zipAsset.Url }
              else { "https://github.com/$repo/releases/download/$tag/$zipName" }

    $zipPath = Invoke-Download -FileName $zipName -Url $zipUrl -BaseDir $Config.BaseDir `
        -LocalBundleDir $Config.LocalBundleDir

    # 3) Extract VapourSynth portable zip
    Write-Host "     Extrayendo VapourSynth..." -ForegroundColor Gray
    if (-not (Test-Path $vsDir)) { New-Item -ItemType Directory -Path $vsDir | Out-Null }
    Expand-Archive -Path $zipPath -DestinationPath $vsDir -Force

    # Verify extraction structure (legacy folder restructuring only for <R74)
    if ($tagNum -lt 74) {
        if (-not (Test-Path $vspipe)) {
            # Some archives have a subdirectory
            $sub = Get-ChildItem $vsDir -Filter "VSPipe.exe" -Recurse | Select-Object -First 1
            if ($sub) {
                # Move contents up
                $subDir = Split-Path $sub.FullName -Parent
                if ($subDir -ne $vsDir) {
                    Get-ChildItem $subDir | Move-Item -Destination $vsDir -Force
                    Remove-Item $subDir -Recurse -Force -EA SilentlyContinue
                }
            }
        }
    }

    # 4) Install VapourSynth Wheel via pip if R74+
    if ($tagNum -ge 74) {
        $wheelDir = Join-Path $vsDir "wheel"
        $wheel = Get-ChildItem $wheelDir -Filter "vapoursynth-*.whl" | Select-Object -First 1
        if ($wheel) {
            Write-Host "     Instalando wheel de VapourSynth ($($wheel.Name))..." -ForegroundColor Gray
            & $pyExe -m pip install --force-reinstall $wheel.FullName --no-warn-script-location | Out-Host
        } else {
            throw "Wheel de VapourSynth no encontrado en el paquete portable"
        }

        # Cleanup get-pip.py and other temporary setup artifacts
        $pipScript = Join-Path $Config.BaseDir "get-pip.py"
        Remove-Item $pipScript -Force -EA SilentlyContinue
    }

    $finalVspipe = if ($tagNum -ge 74) { Join-Path $vsDir "Scripts\vspipe.exe" } else { Join-Path $vsDir "VSPipe.exe" }

    if (Test-Path $finalVspipe) {
        Write-Host "[OK] VapourSynth $tag instalado" -ForegroundColor Green
    } else {
        throw "VapourSynth installation failed - VSPipe.exe not found"
    }

    # Create required subdirectories
    $pluginDir = Join-Path $vsDir "vs-plugins"
    if (-not (Test-Path $pluginDir)) { New-Item -ItemType Directory -Path $pluginDir | Out-Null }

    # Copy DLLs to the mpv folder to satisfy dynamic loading constraints
    Copy-VapourSynthDllsToMpv -VsDir $vsDir -MpvExe $Config.MpvExe

    return $vsDir
}

function Copy-VapourSynthDllsToMpv {
    <#
    .SYNOPSIS
        Copies python3xx.dll, python3.dll, and vsscript.dll (as VSScript.dll) to the mpv.exe directory.
    #>
    param(
        [string]$VsDir,
        [string]$MpvExe
    )

    if (-not $MpvExe -or -not (Test-Path $MpvExe)) {
        Write-Warning "mpv.exe no configurado o no encontrado. No se copiaron los DLLs."
        return
    }

    $mpvDir = Split-Path $MpvExe -Parent
    Write-Host "`n===> Copiando DLLs de VapourSynth a la carpeta de mpv..." -ForegroundColor Cyan

    # Check if mpv is running
    $runningMpv = Get-Process -Name "mpv" -ErrorAction SilentlyContinue
    if ($runningMpv) {
        Write-Warning "mpv.exe esta en ejecucion. Por favor, cierra mpv antes de continuar."
    }

    # 1) Find the python DLL (e.g. python313.dll)
    $pyDll = Get-ChildItem $VsDir -Filter "python3*.dll" | Where-Object { $_.Name -match '^python3\d+\.dll$' } | Select-Object -First 1
    if (-not $pyDll) {
        Write-Warning "No se encontro python3xx.dll en $VsDir"
        return
    }

    # 2) Find python3.dll
    $py3Dll = Join-Path $VsDir "python3.dll"
    if (-not (Test-Path $py3Dll)) {
        Write-Warning "No se encontro python3.dll en $VsDir"
        return
    }

    # 3) Find vsscript.dll / VSScript.dll (prefer site-packages version first)
    $vsscriptDll = Join-Path $VsDir "Lib\site-packages\vapoursynth\vsscript.dll"
    if (-not (Test-Path $vsscriptDll)) {
        $vsscriptDll = Join-Path $VsDir "vsscript.dll"
    }
    if (-not (Test-Path $vsscriptDll)) {
        $vsscriptDll = Join-Path $VsDir "VSScript.dll"
    }
    if (-not (Test-Path $vsscriptDll)) {
        Write-Warning "No se encontro vsscript.dll en $VsDir"
        return
    }

    # 4) Find libvapoursynth.dll (core library for R76+)
    $libvsDll = Join-Path $VsDir "Lib\site-packages\vapoursynth\libvapoursynth.dll"
    if (-not (Test-Path $libvsDll)) {
        $libvsDll = Join-Path $VsDir "libvapoursynth.dll"
    }

    # Clean up any old python3xx.dll in mpv folder to avoid conflict (e.g. python314.dll)
    try {
        Get-ChildItem $mpvDir -Filter "python3*.dll" | Where-Object { $_.Name -match '^python3\d+\.dll$' -and $_.Name -ne $pyDll.Name } | ForEach-Object {
            Write-Host "     Eliminando DLL obsoleto: $($_.Name)" -ForegroundColor Gray
            Remove-Item $_.FullName -Force -EA Stop
        }
    } catch {
        Write-Warning "No se pudo eliminar el DLL obsoleto: $($_.Exception.Message)"
    }

    # Copy files
    try {
        Write-Host "     Copiando $($pyDll.Name) -> $mpvDir" -ForegroundColor Gray
        Copy-Item $pyDll.FullName (Join-Path $mpvDir $pyDll.Name) -Force -ErrorAction Stop

        Write-Host "     Copiando python3.dll -> $mpvDir" -ForegroundColor Gray
        Copy-Item $py3Dll (Join-Path $mpvDir "python3.dll") -Force -ErrorAction Stop

        Write-Host "     Copiando vsscript.dll (como VSScript.dll) -> $mpvDir" -ForegroundColor Gray
        Copy-Item $vsscriptDll (Join-Path $mpvDir "VSScript.dll") -Force -ErrorAction Stop

        if (Test-Path $libvsDll) {
            Write-Host "     Copiando libvapoursynth.dll -> $mpvDir" -ForegroundColor Gray
            Copy-Item $libvsDll (Join-Path $mpvDir "libvapoursynth.dll") -Force -ErrorAction Stop
        }

        Write-Host "[OK] DLLs copiados correctamente a la carpeta de mpv" -ForegroundColor Green
    } catch {
        Write-Error "Error copiando DLLs a la carpeta de mpv: $($_.Exception.Message)"
    }
}

function Test-VapourSynthInstall {
    <#
    .SYNOPSIS
        Checks if VapourSynth is properly installed and returns status.
    #>
    param([string]$BaseDir)
    $vsDir  = Join-Path $BaseDir "vapoursynth-portable"
    
    $vspipe = Join-Path $vsDir "VSPipe.exe"
    if (-not (Test-Path $vspipe)) {
        $vspipe = Join-Path $vsDir "Scripts\vspipe.exe"
    }

    $status = @{
        Installed  = $false
        Path       = $vsDir
        VsPipePath = $vspipe
        Version    = $null
        PluginDir  = $null
    }

    if (Test-Path $vspipe) {
        $status.Installed = $true
        $status.PluginDir = Join-Path $vsDir "vs-plugins"

        # Try to get version
        try {
            $si = New-Object System.Diagnostics.ProcessStartInfo
            $si.FileName               = $vspipe
            $si.Arguments              = "--version"
            $si.RedirectStandardOutput = $true
            $si.RedirectStandardError  = $true
            $si.UseShellExecute        = $false
            $si.CreateNoWindow         = $true

            $p   = [System.Diagnostics.Process]::Start($si)
            $out = $p.StandardOutput.ReadToEnd()
            $p.WaitForExit(3000)

            $m = [regex]::Match($out, '(?i)\b(?:Core|VapourSynth)\s+(R\d+)\b')
            if ($m.Success) { $status.Version = $m.Groups[1].Value }
        } catch {}
    }

    return $status
}

Export-ModuleMember -Function Install-VapourSynth, Test-VapourSynthInstall, Copy-VapourSynthDllsToMpv
