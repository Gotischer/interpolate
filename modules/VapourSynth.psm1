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

    return $vsDir
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

Export-ModuleMember -Function Install-VapourSynth, Test-VapourSynthInstall
