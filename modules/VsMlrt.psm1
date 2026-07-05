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

    # Determine which bundle to download based on backend.
    # Contenido de cada bundle (verificado en el workflow de release de vs-mlrt):
    #   cuda         : VSOV + VSORT + VSTRT + VSTRT-RTX + VSNCNN + libs CUDA
    #                  (cublas/cudnn/cufft/cupti/nvblas) — para NVIDIA Turing+
    #   generic-gpu  : VSOV + VSORT + VSNCNN (GPU) — sin CUDA, para Pascal,
    #                  AMD, Intel via Vulkan
    #   tensorrt     : igual a cuda PERO sin las libs CUDA. No sirve standalone
    #                  porque TensorRT 10 las necesita en runtime.
    #   cpu          : VSOV + VSORT — sin GPU, fallback CPU
    # El backend MVTOOLS no llama a Install-VsMlrt (la rama del wizard se
    # saltea esto), pero igual mapeamos a cpu por completitud.
    $bundlePattern = switch ($BackendType) {
        "TRT"      { "vsmlrt-windows-x64-cuda" }
        "TRT_RTX"  { "vsmlrt-windows-x64-cuda" }
        "NCNN_VK"  { "vsmlrt-windows-x64-generic-gpu" }
        "MVTOOLS"  { "vsmlrt-windows-x64-cpu" }
        default    { "vsmlrt-windows-x64-cuda" }
    }

    # Find matching assets (could be split: .7z.001, .7z.002, or single .7z)
    $matchingAssets = $rel.Assets | Where-Object { $_.Name -match $bundlePattern }

    # Fallback: vs-mlrt renombro algunos bundles entre releases (p.ej. el
    # NCNN/Vulkan se llamo "vulkan" en versiones viejas, ahora "generic-gpu").
    # Si el patron primario no matchea, probamos alternativas conocidas en
    # vez de tirar throw inmediatamente.
    if ($matchingAssets.Count -eq 0) {
        $fallbackPatterns = switch ($BackendType) {
            "TRT"      { @("vsmlrt-windows-x64-tensorrt") }    # ojo: sin CUDA libs
            "TRT_RTX"  { @("vsmlrt-windows-x64-tensorrt") }
            "NCNN_VK"  { @("vsmlrt-windows-x64-vulkan",       # nombre viejo
                           "VSNCNN-Windows-x64") }            # plugin standalone
            "MVTOOLS"  { @("vsmlrt-windows-x64-generic-gpu") }
            default    { @() }
        }
        foreach ($alt in $fallbackPatterns) {
            $matchingAssets = $rel.Assets | Where-Object { $_.Name -match $alt }
            if ($matchingAssets.Count -gt 0) {
                Write-Host "     Bundle primario '$bundlePattern' no encontrado, usando fallback '$alt'" -ForegroundColor Yellow
                $bundlePattern = $alt
                break
            }
        }
    }

    if ($matchingAssets.Count -eq 0) {
        Write-Host "[!!] No se encontraron assets para '$bundlePattern' ni fallbacks" -ForegroundColor Yellow
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

    # Install vsmlrt.py: vive en un asset separado (scripts.<tag>.7z) que NO
    # esta en el bundle de plugins. Sin este archivo el .vpy revienta con
    # "ModuleNotFoundError: No module named 'vsmlrt'". El diagnostico marca
    # "vsmlrt.py no encontrado" y "Re-parchear" no hace nada porque
    # Invoke-VsmlrtPatch silenciosamente retorna 0 si el archivo no existe.
    Install-VsmlrtScripts -Config $Config -VsDir $VsDir -Release $rel | Out-Null

    Write-Host "[OK] vs-mlrt $($rel.Tag) instalado ($BackendType)" -ForegroundColor Green
    return $rel.Tag
}

function Install-VsmlrtScripts {
    <#
    .SYNOPSIS
        Downloads and installs the vs-mlrt scripts asset (vsmlrt.py and
        friends) into <vsDir>/Lib/site-packages/.
    .DESCRIPTION
        The vs-mlrt GitHub release ships the python wrapper (vsmlrt.py) as a
        separate ~17 KB asset named "scripts.<tag>.7z", NOT inside the main
        plugin bundle. This function handles that asset specifically.
    #>
    param(
        [hashtable]$Config,
        [string]$VsDir,
        $Release = $null
    )
    if (-not $Release) {
        $Release = Get-LatestGithubRelease -Repo "AmusementClub/vs-mlrt"
    }
    if (-not $Release) {
        throw "No se pudo obtener release de vs-mlrt para descargar scripts"
    }

    $sitePkg = Join-Path $VsDir "Lib\site-packages"
    if (-not (Test-Path $sitePkg)) { New-Item -ItemType Directory -Path $sitePkg -Force | Out-Null }

    # El asset se llama "scripts.<tag>.7z" (ej. scripts.v15.16.7z).
    $scriptsAsset = $Release.Assets |
        Where-Object { $_.Name -match '^scripts\..*\.7z$' } |
        Select-Object -First 1

    if (-not $scriptsAsset) {
        Write-Host "[!!] No encontre asset scripts.*.7z en vs-mlrt $($Release.Tag)" -ForegroundColor Yellow
        Write-Host "     vsmlrt.py no se instalara automaticamente." -ForegroundColor DarkGray
        return $null
    }

    Write-Host "     Descargando vsmlrt.py ($($scriptsAsset.Name))..." -ForegroundColor Gray
    $scriptsArchive = Invoke-Download -FileName $scriptsAsset.Name -Url $scriptsAsset.Url `
        -BaseDir $Config.BaseDir -LocalBundleDir $Config.LocalBundleDir `
        -ExpectedSize $scriptsAsset.Size

    $tmpDir = Join-Path $Config.BaseDir "vsmlrt-scripts-tmp"
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    Expand-7zArchive -Archive $scriptsArchive -DestDir $tmpDir -BaseDir $Config.BaseDir

    # Copiamos cualquier .py al site-packages (vsmlrt.py es el principal pero
    # algunos releases incluyen helpers extra).
    $pyFiles = Get-ChildItem $tmpDir -Filter "*.py" -Recurse -EA SilentlyContinue
    foreach ($f in $pyFiles) {
        Copy-Item $f.FullName (Join-Path $sitePkg $f.Name) -Force
        Write-Host "     site-packages/$($f.Name)" -ForegroundColor DarkGray
    }

    Remove-Item $tmpDir -Recurse -Force -EA SilentlyContinue

    $vsmlrtPy = Join-Path $sitePkg "vsmlrt.py"
    if (Test-Path $vsmlrtPy) {
        Write-Host "[OK] vsmlrt.py instalado" -ForegroundColor Green
        return $vsmlrtPy
    } else {
        Write-Host "[!!] scripts.7z extraido pero vsmlrt.py no aparecio" -ForegroundColor Yellow
        return $null
    }
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
    $rel  = Get-LatestGithubRelease -Repo $repo -RequireAssetMatch "rife_*.7z"

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
    .DESCRIPTION
        vs-mlrt ships in varias flavors:
          - cuda        => trtexec.exe + vstrt.dll + vstrt_rtx.dll + vsncnn.dll
          - generic-gpu => vsncnn.dll + vsov.dll + vsort.dll (sin TRT, sin CUDA)
          - cpu         => vsov.dll + vsort.dll (subset)
        El chequeo anterior solo buscaba trtexec/vstrt y por eso un install
        NCNN_VK (Pascal/AMD/Intel) daba "FAIL No instalado" aunque tuviera
        vsncnn.dll y los modelos. Ahora consideramos instalado si EXISTE
        cualquier plugin DLL conocido, y guardamos cuales encontramos.
    #>
    param([string]$VsDir)
    $pluginDir = Join-Path $VsDir "vs-plugins"

    $status = @{
        Installed     = $false
        TrtExec       = $false
        Backends      = @()
        ModelsDir     = $null
        ModelCount    = 0
        VsmlrtPy      = $null
        VsmlrtPatched = $false
    }

    # Buscamos cualquier plugin de vs-mlrt (TRT / NCNN / OV / ORT)
    $trt      = Get-ChildItem $pluginDir -Filter "trtexec.exe"     -Recurse -EA SilentlyContinue | Select-Object -First 1
    $vstrt    = Get-ChildItem $pluginDir -Filter "vstrt.dll"       -Recurse -EA SilentlyContinue | Select-Object -First 1
    $vstrtrtx = Get-ChildItem $pluginDir -Filter "vstrt_rtx.dll"   -Recurse -EA SilentlyContinue | Select-Object -First 1
    $vsncnn   = Get-ChildItem $pluginDir -Filter "vsncnn.dll"      -Recurse -EA SilentlyContinue | Select-Object -First 1
    $vsov     = Get-ChildItem $pluginDir -Filter "vsov.dll"        -Recurse -EA SilentlyContinue | Select-Object -First 1
    $vsort    = Get-ChildItem $pluginDir -Filter "vsort.dll"       -Recurse -EA SilentlyContinue | Select-Object -First 1

    if ($trt)      { $status.TrtExec = $true }
    if ($vstrt)    { $status.Backends += 'TRT' }
    if ($vstrtrtx) { $status.Backends += 'TRT_RTX' }
    if ($vsncnn)   { $status.Backends += 'NCNN' }
    if ($vsov)     { $status.Backends += 'OV' }
    if ($vsort)    { $status.Backends += 'ORT' }

    if ($status.Backends.Count -gt 0) { $status.Installed = $true }

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

function Install-MVTools {
    <#
    .SYNOPSIS
        Descarga e instala el plugin MVTools en vs-plugins/.
    .DESCRIPTION
        MVTools (vapoursynth-mvtools de dubhater) no esta incluido en los
        bundles de vs-mlrt. Se distribuye como release separado en
        https://github.com/dubhater/vapoursynth-mvtools/releases.

        Es el unico backend de interpolacion usable en GPUs pre-Turing
        (Pascal, Maxwell, Kepler, GTX 9xx y mas viejas) porque:
          - TRT 10 no soporta sm_<7.5
          - NCNN no implementa GridSample (necesario para RIFE)
          - ORT_DML es tecnicamente compatible pero demasiado lento

        MVTools usa motion vectors CPU, es muy liviano (corre suave en
        cualquier procesador moderno) y produce interpolacion de calidad
        razonable para video general.
    #>
    param(
        [hashtable]$Config,
        [string]$VsDir
    )
    Write-Host "`n===> Instalando MVTools" -ForegroundColor Cyan

    $pluginDir = Join-Path $VsDir "vs-plugins"
    if (-not (Test-Path $pluginDir)) { New-Item -ItemType Directory -Path $pluginDir | Out-Null }

    # Las ultimas 3 releases (v25, v26, v27) en dubhater/vapoursynth-mvtools
    # NO publican assets binarios (solo source tarballs auto-generados por
    # GitHub). La ultima con DLLs precompiladas para Windows es v24.
    # Iteramos releases descendente hasta encontrar una con asset win64 .7z.
    $repo = "dubhater/vapoursynth-mvtools"
    Write-Host "     Buscando ultima release con binarios Windows..." -ForegroundColor Gray
    $relList = $null
    try {
        $relList = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases?per_page=15" `
            -Headers @{ 'User-Agent' = 'mpv-interp-wizard' } -EA Stop
    } catch {
        throw "No se pudo obtener releases de MVTools: $($_.Exception.Message)"
    }

    $rel = $null
    $asset = $null
    foreach ($r in $relList) {
        $candidate = $r.assets |
            Where-Object {
                $_.name -match "win64|x86_64|x64" -and
                $_.name -notmatch "win32" -and
                $_.name -notmatch "glibc" -and
                $_.name -match "\.7z$"
            } |
            Select-Object -First 1
        if ($candidate) {
            $rel = @{ Tag = $r.tag_name }
            $asset = @{ Name = $candidate.name; Url = $candidate.browser_download_url; Size = $candidate.size }
            break
        }
    }

    if (-not $asset) {
        throw "No se encontro release de MVTools con binarios Windows x64. " +
              "Revisa $repo/releases manualmente."
    }
    Write-Host "     Version: $($rel.Tag) ($($asset.Name))" -ForegroundColor Gray

    $archive = Invoke-Download -FileName $asset.Name -Url $asset.Url `
        -BaseDir $Config.BaseDir -LocalBundleDir $Config.LocalBundleDir `
        -ExpectedSize $asset.Size

    $tmpDir = Join-Path $Config.BaseDir "mvtools-tmp"
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    Expand-7zArchive -Archive $archive -DestDir $tmpDir -BaseDir $Config.BaseDir

    # Copiar la DLL (libmvtools.dll o similar) a vs-plugins/
    $copied = 0
    Get-ChildItem $tmpDir -Filter "*.dll" -Recurse | ForEach-Object {
        $dest = Join-Path $pluginDir $_.Name
        Copy-Item $_.FullName $dest -Force
        Write-Host "     $($_.Name)" -ForegroundColor DarkGray
        $copied++
    }
    Remove-Item $tmpDir -Recurse -Force -EA SilentlyContinue

    if ($copied -eq 0) {
        throw "MVTools archive no contiene DLLs"
    }
    Write-Host "[OK] MVTools $($rel.Tag) instalado" -ForegroundColor Green
    return $rel.Tag
}

Export-ModuleMember -Function Install-VsMlrt, Install-VsmlrtScripts, Install-RIFEModels, Install-MVTools, Test-VsMlrtInstall
