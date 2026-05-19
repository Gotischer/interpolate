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
        [string]$TargetRelease = "R76"
    )
    $vsDir = Join-Path $Config.BaseDir "vapoursynth-portable"

    if (Test-Path (Join-Path $vsDir "VSPipe.exe")) {
        Write-Host "[OK] VapourSynth ya instalado en $vsDir" -ForegroundColor Green
        return $vsDir
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

    # Look for the portable zip in assets
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

    # Extract
    Write-Host "     Extrayendo VapourSynth..." -ForegroundColor Gray
    if (-not (Test-Path $vsDir)) { New-Item -ItemType Directory -Path $vsDir | Out-Null }
    Expand-Archive -Path $zipPath -DestinationPath $vsDir -Force

    # Verify
    $vspipe = Join-Path $vsDir "VSPipe.exe"
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

    if (Test-Path (Join-Path $vsDir "VSPipe.exe")) {
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

            $m = [regex]::Match($out, 'VapourSynth\s+(R\d+)')
            if ($m.Success) { $status.Version = $m.Groups[1].Value }
        } catch {}
    }

    return $status
}

Export-ModuleMember -Function Install-VapourSynth, Test-VapourSynthInstall
