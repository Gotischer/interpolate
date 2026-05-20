# =============================================================================
#  VsMlrt.psm1 — vs-mlrt bundle installation (RIFE + TensorRT/NCNN)
#
#  Handles: download (split archives .001/.002), extraction, model installation,
#  and version management for the AmusementClub/vs-mlrt plugin bundle.
# =============================================================================

function Install-VsMlrt {
    <#
    .SYNOPSIS
        Downloads and installs the vs-mlrt backend bundle.
    .PARAMETER BackendType
        "TRT" for TensorRT (NVIDIA), "NCNN_VK" for NCNN/Vulkan (AMD/Intel/old NVIDIA)
    #>
    param(
        [hashtable]$Config,
        [string]$BackendType = "TRT",
        [string]$VsDir
    )

    $pluginDir = Join-Path $VsDir "vs-plugins"
    if (-not (Test-Path $pluginDir)) { New-Item -ItemType Directory -Path $pluginDir | Out-Null }

    Write-Host "`n===> Instalando vs-mlrt ($BackendType)" -ForegroundColor Cyan

    $repo = "AmusementClub/vs-mlrt"
    $rel  = Get-LatestGithubRelease -Repo $repo

    if (-not $rel) {
        throw "No se pudo obtener la release de vs-mlrt desde GitHub"
    }

    Write-Host "     Versión: $($rel.Tag)" -ForegroundColor Gray

    # Determine which bundle to download based on backend
    $bundlePattern = switch ($BackendType) {
        "TRT"     { "vsmlrt-windows-x64-cuda" }
        "NCNN_VK" { "vsmlrt-windows-x64-vulkan" }
        default   { "vsmlrt-windows-x64-cuda" }
    }

    # Find matching assets (could be split: .7z.001, .7z.002, or single .7z)
    $matchingAssets = $rel.Assets | Where-Object { $_.Name -match $bundlePattern }

    if ($matchingAssets.Count -eq 0) {
        Write-Host "[!!] No se encontraron assets para '$bundlePattern'" -ForegroundColor Yellow
        Write-Host "     Assets disponibles:" -ForegroundColor DarkGray
        foreach ($a in $rel.Assets) { Write-Host "       $($a.Name)" -ForegroundColor DarkGray }
        throw "vs-mlrt bundle not found for backend $BackendType"
    }

    # Check for split archive pattern
    $splitParts = $matchingAssets | Where-Object { $_.Name -match '\.\d{3}$' } | Sort-Object { $_.Name }

    if ($splitParts.Count -gt 0) {
        # Split archive
        Write-Host "     Archivo dividido ($($splitParts.Count) partes)" -ForegroundColor Gray
        $firstPart = $null
        foreach ($part in $splitParts) {
            $path = Invoke-Download -FileName $part.Name -Url $part.Url `
                -BaseDir $Config.BaseDir -LocalBundleDir $Config.LocalBundleDir `
                -ExpectedSize $part.Size
            if (-not $firstPart) { $firstPart = $path }
        }
        $archivePath = $firstPart
    } else {
        # Single archive
        $asset = $matchingAssets | Select-Object -First 1
        $archivePath = Invoke-Download -FileName $asset.Name -Url $asset.Url `
            -BaseDir $Config.BaseDir -LocalBundleDir $Config.LocalBundleDir `
            -ExpectedSize $asset.Size
    }

    # Extract to temp, then move to plugin dir
    $tmpDir = Join-Path $Config.BaseDir "vsmlrt-tmp"
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }

    Expand-7zArchive -Archive $archivePath -DestDir $tmpDir -BaseDir $Config.BaseDir

    # Copy files from root without recursing into subdirectories
    Get-ChildItem $tmpDir -File | ForEach-Object {
        $dest = Join-Path $pluginDir $_.Name
        Copy-Item $_.FullName $dest -Force
        Write-Host "     $($_.Name)" -ForegroundColor DarkGray
    }

    # Copy backend subdirectories (e.g. vsmlrt-cuda, vsort, vsov) recursively
    Get-ChildItem $tmpDir -Directory | ForEach-Object {
        $destSub = Join-Path $pluginDir $_.Name
        if (-not (Test-Path $destSub)) { New-Item -ItemType Directory -Path $destSub | Out-Null }
        Copy-Item (Join-Path $_.FullName "*") $destSub -Recurse -Force
        Write-Host "     $($_.Name)/" -ForegroundColor DarkGray
    }

    # Cleanup
    Remove-Item $tmpDir -Recurse -Force -EA SilentlyContinue

    Write-Host "[OK] vs-mlrt $($rel.Tag) instalado ($BackendType)" -ForegroundColor Green
    return $rel.Tag
}

function Install-RIFEModels {
    <#
    .SYNOPSIS
        Downloads and installs RIFE ONNX model files.
    .PARAMETER Models
        Array of model keys to install (e.g., "v4.25_heavy", "v4.25")
    #>
    param(
        [hashtable]$Config,
        [string]$VsDir,
        [string[]]$Models = @("v4.25_heavy", "v4.25")
    )

    $pluginDir = Join-Path $VsDir "vs-plugins"
    $modelsDir = Join-Path $pluginDir "models"
    $rifeDir   = Join-Path $modelsDir "rife"
    if (-not (Test-Path $rifeDir)) { New-Item -ItemType Directory -Path $rifeDir -Force | Out-Null }

    Write-Host "`n===> Instalando modelos RIFE" -ForegroundColor Cyan

    $repo = "AmusementClub/vs-mlrt"
    $rel  = Get-LatestGithubRelease -Repo $repo

    if (-not $rel) { throw "No se pudo obtener releases de vs-mlrt" }

    # Check which models are already installed
    $missing = @()
    foreach ($m in $Models) {
        $onnxPattern = "rife_$($m -replace '_', '_')*"
        $existing = Get-ChildItem $rifeDir -Filter $onnxPattern -EA SilentlyContinue
        if (-not $existing -or $existing.Count -eq 0) { $missing += $m }
        else { Write-Host "     $m ya instalado ($($existing.Count) archivos)" -ForegroundColor Gray }
    }

    if ($missing.Count -eq 0) {
        Write-Host "[OK] Todos los modelos ya están instalados" -ForegroundColor Green
        return
    }

    foreach ($model in $missing) {
        $assetName = "rife_$model.7z"
        $asset     = $rel.Assets | Where-Object { $_.Name -eq $assetName } | Select-Object -First 1

        if (-not $asset) {
            Write-Host "[!!] No encontré $assetName en los assets" -ForegroundColor Yellow
            continue
        }

        $archPath = Invoke-Download -FileName $asset.Name -Url $asset.Url `
            -BaseDir $Config.BaseDir -LocalBundleDir $Config.LocalBundleDir `
            -ExpectedSize $asset.Size

        $tmpDir = Join-Path $Config.BaseDir "rife-model-tmp"
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }

        Expand-7zArchive -Archive $archPath -DestDir $tmpDir -BaseDir $Config.BaseDir

        $onnxFiles = Get-ChildItem $tmpDir -Filter "*.onnx" -Recurse
        foreach ($f in $onnxFiles) {
            Copy-Item $f.FullName (Join-Path $rifeDir $f.Name) -Force
            Write-Host "     rife/$($f.Name)" -ForegroundColor DarkGray
        }

        Remove-Item $tmpDir -Recurse -Force -EA SilentlyContinue
    }

    Write-Host "[OK] Modelos RIFE instalados" -ForegroundColor Green
}

function Test-VsMlrtInstall {
    <#
    .SYNOPSIS
        Checks if vs-mlrt is properly installed.
    #>
    param([string]$VsDir)
    $pluginDir = Join-Path $VsDir "vs-plugins"

    $status = @{
        Installed     = $false
        TrtExec       = $false
        ModelsDir     = $null
        ModelCount    = 0
        VsmlrtPy      = $null
        VsmlrtPatched = $false
    }

    # Check for trtexec.exe (TensorRT) or vstrt.dll
    $trt = Get-ChildItem $pluginDir -Filter "trtexec.exe" -Recurse -EA SilentlyContinue | Select-Object -First 1
    $vstrt = Get-ChildItem $pluginDir -Filter "vstrt.dll" -Recurse -EA SilentlyContinue | Select-Object -First 1

    if ($trt -or $vstrt) { $status.Installed = $true }
    if ($trt)  { $status.TrtExec = $true }

    # Check models
    $modelsDir = Join-Path $pluginDir "models"
    if (Test-Path $modelsDir) {
        $status.ModelsDir  = $modelsDir
        $status.ModelCount = (Get-ChildItem $modelsDir -Filter "*.onnx" -Recurse -EA SilentlyContinue).Count
    }

    # Check vsmlrt.py
    $vsmlrtPy = Join-Path (Split-Path $pluginDir -Parent) "Lib\site-packages\vsmlrt.py"
    if (Test-Path $vsmlrtPy) {
        $status.VsmlrtPy = $vsmlrtPy
        $content = Get-Content $vsmlrtPy -Raw -EA SilentlyContinue
        $status.VsmlrtPatched = $content -and
            $content.Contains('except AttributeError:') -and
            $content.Contains('**os.environ')
    }

    return $status
}

Export-ModuleMember -Function Install-VsMlrt, Install-RIFEModels, Test-VsMlrtInstall
