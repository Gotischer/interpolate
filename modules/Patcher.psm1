# =============================================================================
#  Patcher.psm1 — Robust patching of vsmlrt.py
#
#  Patches the vs-mlrt Python module to:
#  1. Add try/except around trt_version (prevents crash if TRT not loaded)
#  2. Inject CUDA directory into PATH (required for TensorRT runtime)
#  3. Spread os.environ into subprocess env (fixes missing env vars)
#  4. Remove flexible_output=True (causes errors in newer vsmlrt)
#
#  Uses regex-based matching for robustness and idempotency.
# =============================================================================

function Invoke-VsmlrtPatch {
    <#
    .SYNOPSIS
        Applies all necessary patches to vsmlrt.py. Idempotent.
    .PARAMETER Path
        Full path to vsmlrt.py
    .RETURNS
        Number of patches applied (0 = already patched or nothing to do)
    #>
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Host "[!!] vsmlrt.py no encontrado: $Path" -ForegroundColor Yellow
        return 0
    }

    $content = Get-Content $Path -Raw -Encoding UTF8
    $original = $content
    $patchCount = 0

    # Build the CUDA directory expression
    $cudaExpr = 'str(__import__("pathlib").Path(__file__).parent / "vsmlrt-cuda")'

    # --- Patch 1: TRT version try/except (core.trt.Version) ---
    # Match the exact unpatched line, not an already-patched one
    $p1_pattern = '(?m)^(        )trt_version = parse_trt_version\(int\(core\.trt\.Version\(\)\[\"tensorrt_version\"\]\)\)\s*$'
    if ($content -match $p1_pattern -and $content -notmatch '(?m)^\s+try:\s*\n\s+trt_version = parse_trt_version\(int\(core\.trt\.Version') {
        $p1_replace = @'
        try:
            trt_version = parse_trt_version(int(core.trt.Version()["tensorrt_version"]))
        except AttributeError:
            trt_version = (10, 16, 0)
'@
        $content = [regex]::Replace($content, $p1_pattern, ($p1_replace -replace '\$', '$$$$'))
        $patchCount++
    }

    # --- Patch 2: TRT_RTX version try/except (core.trt_rtx.Version) ---
    $p2_pattern = '(?m)^(    )trt_version = parse_trt_version\(int\(core\.trt_rtx\.Version\(\)\[\"tensorrt_version\"\]\)\)\s*$'
    if ($content -match $p2_pattern -and $content -notmatch '(?m)^\s+try:\s*\n\s+trt_version = parse_trt_version\(int\(core\.trt_rtx\.Version') {
        $p2_replace = @'
    try:
        trt_version = parse_trt_version(int(core.trt_rtx.Version()["tensorrt_version"]))
    except AttributeError:
        trt_version = (10, 16, 0)
'@
        $content = [regex]::Replace($content, $p2_pattern, ($p2_replace -replace '\$', '$$$$'))
        $patchCount++
    }

    # --- Patch 3: Inject CUDA path + spread os.environ (env with prev_env_value) ---
    $p3_pattern = '(?m)^(\s+)env = \{env_key: prev_env_value, \"CUDA_MODULE_LOADING\": \"LAZY\"\}\s*$'
    if ($content -match $p3_pattern -and $content -notmatch '\*\*os\.environ.*env_key:\s*prev_env_value') {
        $p3_replace = @"
            _cuda_dir = $cudaExpr
            env = {**os.environ, env_key: prev_env_value, "CUDA_MODULE_LOADING": "LAZY", "PATH": _cuda_dir + ";" + os.environ.get("PATH", "")}
"@
        $content = [regex]::Replace($content, $p3_pattern, ($p3_replace -replace '\$', '$$$$'))
        $patchCount++
    }

    # --- Patch 4: Inject CUDA path + spread os.environ (env with log_filename) ---
    $p4_pattern = '(?m)^(\s+)env = \{env_key: log_filename, \"CUDA_MODULE_LOADING\": \"LAZY\"\}\s*$'
    if ($content -match $p4_pattern -and $content -notmatch '\*\*os\.environ.*env_key:\s*log_filename') {
        $p4_replace = @"
            _cuda_dir = $cudaExpr
            env = {**os.environ, env_key: log_filename, "CUDA_MODULE_LOADING": "LAZY", "PATH": _cuda_dir + ";" + os.environ.get("PATH", "")}
"@
        $content = [regex]::Replace($content, $p4_pattern, ($p4_replace -replace '\$', '$$$$'))
        $patchCount++
    }

    # --- Patch 5: Inject CUDA path + spread os.environ (bare CUDA_MODULE_LOADING) ---
    $p5_pattern = '(?m)^(\s+)env = \{\"CUDA_MODULE_LOADING\": \"LAZY\"\}\s*$'
    if ($content -match $p5_pattern -and $content -notmatch '\*\*os\.environ.*\"CUDA_MODULE_LOADING\"') {
        $p5_replace = @"
        _cuda_dir = $cudaExpr
        env = {**os.environ, "CUDA_MODULE_LOADING": "LAZY", "PATH": _cuda_dir + ";" + os.environ.get("PATH", "")}
"@
        $content = [regex]::Replace($content, $p5_pattern, ($p5_replace -replace '\$', '$$$$'))
        $patchCount++
    }

    # --- Patch 6: Remove flexible_output=True ---
    if ($content -match 'flexible_output=True') {
        $content = $content -replace ',?\s*flexible_output=True', ''
        $patchCount++
    }

    # Save only if changes were made
    if ($content -ne $original) {
        Set-Content $Path $content -NoNewline -Encoding UTF8
        Write-Host "[OK] vsmlrt.py parcheado ($patchCount parches aplicados)" -ForegroundColor Green
    } else {
        Write-Host "     vsmlrt.py ya está parcheado (nada que hacer)" -ForegroundColor Gray
    }

    return $patchCount
}

function Restore-VsmlrtPy {
    <#
    .SYNOPSIS
        Restores vsmlrt.py from the vs-mlrt bundle (re-extract + re-patch).
    #>
    param(
        [string]$VsDir,
        [hashtable]$Config
    )

    Write-Host "`n===> Restaurando vsmlrt.py" -ForegroundColor Cyan

    $vsmlrtPy = Join-Path $VsDir "Lib\site-packages\vsmlrt.py"

    # Try to find a backup
    $bak = "$vsmlrtPy.original"
    if (Test-Path $bak) {
        Copy-Item $bak $vsmlrtPy -Force
        Write-Host "     Restaurado desde backup original" -ForegroundColor Gray
    } else {
        Write-Host "[!!] No hay backup de vsmlrt.py - reinstalar vs-mlrt" -ForegroundColor Yellow
        return $false
    }

    # Re-apply patches
    $patches = Invoke-VsmlrtPatch -Path $vsmlrtPy
    return $true
}

function Backup-VsmlrtPy {
    <#
    .SYNOPSIS
        Creates a backup of the original (unpatched) vsmlrt.py.
    #>
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    $bak = "$Path.original"
    if (-not (Test-Path $bak)) {
        Copy-Item $Path $bak -Force
        Write-Host "     Backup creado: vsmlrt.py.original" -ForegroundColor DarkGray
    }
}

Export-ModuleMember -Function Invoke-VsmlrtPatch, Restore-VsmlrtPy, Backup-VsmlrtPy
