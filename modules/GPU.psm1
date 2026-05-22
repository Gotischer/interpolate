# =============================================================================
#  GPU.psm1 — GPU detection, backend selection, and profile matching
#
#  Detects: GPU model, vendor, generation, compute capability, driver version.
#  Returns: recommended backend + RIFE parameters from gpu-profiles.json.
# =============================================================================

function Detect-GPU {
    <#
    .SYNOPSIS
        Detects the primary GPU and returns a structured environment object.
    .OUTPUTS
        Hashtable with keys: GPU, GPUVendor, GPUGen, ComputeCap, SupportedBackend,
        DriverVersion, ProfileKey
    #>
    $env = @{
        GPU              = $null
        GPUVendor        = $null
        GPUGen           = $null
        ComputeCap       = $null
        SupportedBackend = $null
        DriverVersion    = $null
        ProfileKey       = "Fallback"
    }

    try {
        $gpus = Get-CimInstance Win32_VideoController -EA SilentlyContinue |
                Where-Object { $_.Name -notlike "*Basic*" -and $_.Name -notlike "*Microsoft*" }

        if (-not $gpus) {
            $env.GPU              = "No dedicada"
            $env.GPUVendor        = "Unknown"
            $env.SupportedBackend = "MVTOOLS"
            return $env
        }

        # Prioritize: NVIDIA > AMD > Intel > Other
        $primary = $gpus | Where-Object { $_.Name -like "*NVIDIA*" } | Select-Object -First 1
        if (-not $primary) {
            $primary = $gpus | Where-Object { $_.Name -like "*AMD*" -or $_.Name -like "*Radeon*" } | Select-Object -First 1
        }
        if (-not $primary) { $primary = $gpus | Select-Object -First 1 }

        $env.GPU = $primary.Name
        $name    = $primary.Name.ToLower()

        if ($name -match "nvidia|geforce|rtx|gtx") {
            $env.GPUVendor     = "NVIDIA"
            $env.DriverVersion = $primary.DriverVersion

            if ($name -match "rtx\s*50[0-9]{2}|rtx\s*pro\s*6") {
                $env.GPUGen           = "Blackwell"
                $env.ComputeCap       = "12.0"
                $env.SupportedBackend = "RIFE_TRT"
                $env.ProfileKey       = "Blackwell"
            }
            elseif ($name -match "rtx\s*40[0-9]{2}") {
                $env.GPUGen           = "Ada Lovelace"
                $env.ComputeCap       = "8.9"
                $env.SupportedBackend = "RIFE_TRT"
                $env.ProfileKey       = "Ada"
            }
            elseif ($name -match "rtx\s*30[0-9]{2}") {
                $env.GPUGen           = "Ampere"
                $env.ComputeCap       = "8.6"
                $env.SupportedBackend = "RIFE_TRT"
                $env.ProfileKey       = "Ampere"
            }
            elseif ($name -match "rtx\s*20[0-9]{2}|gtx\s*16[0-9]{2}|titan\s*rtx") {
                $env.GPUGen           = "Turing"
                $env.ComputeCap       = "7.5"
                $env.SupportedBackend = "RIFE_TRT"
                $env.ProfileKey       = "Turing"
            }
            elseif ($name -match "gtx\s*10[0-9]{2}|titan\s*xp|titan\s*x") {
                $env.GPUGen           = "Pascal"
                $env.ComputeCap       = "6.1"
                # Cadena de incompatibilidades en Pascal:
                #   - TRT/TRT_RTX: TensorRT 10 dropeo sm_61 (no esta en
                #     nvinfer_builder_resource_smXX_10.dll).
                #   - NCNN_VK: el build de vs-mlrt no implementa GridSample,
                #     que es operacion fundamental de RIFE.
                #   - ORT_DML: tecnicamente carga, pero la GTX 1060 toma
                #     100-200 ms por frame a 1080p (medido) - inviable.
                # MVTools usa CPU motion vectors, es muy liviano y entrega
                # interpolacion fluida en hardware viejo.
                $env.SupportedBackend = "MVTOOLS"
                $env.ProfileKey       = "Pascal"
            }
            else {
                $env.GPUGen           = "NVIDIA antigua"
                $env.SupportedBackend = "MVTOOLS"
                $env.ProfileKey       = "NVIDIA_Old"
            }
        }
        elseif ($name -match "amd|radeon|rx\s") {
            $env.GPUVendor = "AMD"
            if ($name -match "rx\s*7[0-9]{3}") {
                $env.GPUGen           = "RDNA3"
                $env.SupportedBackend = "RIFE_NCNN"
                $env.ProfileKey       = "AMD_RDNA3"
            }
            elseif ($name -match "rx\s*6[0-9]{3}") {
                $env.GPUGen           = "RDNA2"
                $env.SupportedBackend = "RIFE_NCNN"
                $env.ProfileKey       = "AMD_RDNA2"
            }
            else {
                $env.GPUGen           = "AMD antigua"
                $env.SupportedBackend = "RIFE_NCNN"
                $env.ProfileKey       = "AMD_Old"
            }
        }
        elseif ($name -match "intel.*arc|arc\s+[ab]") {
            $env.GPUVendor        = "Intel"
            $env.GPUGen           = "Arc"
            $env.SupportedBackend = "RIFE_NCNN"
            $env.ProfileKey       = "Intel_Arc"
        }
        elseif ($name -match "iris\s+xe|iris\s+plus") {
            $env.GPUVendor        = "Intel"
            $env.GPUGen           = "Iris Xe"
            $env.SupportedBackend = "RIFE_NCNN"
            $env.ProfileKey       = "iGPU_Xe"
        }
        elseif ($name -match "intel|uhd|hd\s+graphics") {
            $env.GPUVendor        = "Intel"
            $env.GPUGen           = "iGPU"
            $env.SupportedBackend = "MVTOOLS"
            $env.ProfileKey       = "Fallback"
        }
        else {
            $env.GPUVendor        = "Unknown"
            $env.SupportedBackend = "MVTOOLS"
            $env.ProfileKey       = "Fallback"
        }
    }
    catch {
        $env.GPU              = "Error de detección"
        $env.SupportedBackend = "MVTOOLS"
        $env.ProfileKey       = "Fallback"
    }

    return $env
}

function Get-GPUProfile {
    <#
    .SYNOPSIS
        Loads the GPU profile from gpu-profiles.json based on the detected ProfileKey.
    .PARAMETER ProfileKey
        Key from Detect-GPU output (e.g., "Blackwell", "Pascal", "AMD_RDNA3")
    .PARAMETER ProfilesPath
        Path to gpu-profiles.json. If not specified, looks in the script's profiles/ dir.
    #>
    param(
        [string]$ProfileKey = "Fallback",
        [string]$ProfilesPath
    )

    if (-not $ProfilesPath) {
        # Look for profiles relative to the module location
        $moduleDir = Split-Path $PSScriptRoot -Parent
        $ProfilesPath = Join-Path $moduleDir "profiles\gpu-profiles.json"
    }

    if (-not (Test-Path $ProfilesPath)) {
        Write-Warning "gpu-profiles.json not found at $ProfilesPath, using defaults"
        return @{
            label     = "Fallback"
            backend   = "MVTOOLS"
            model     = $null
            fp16      = $false
            streams   = 1
            workspace = $null
        }
    }

    $data    = Get-Content $ProfilesPath -Raw | ConvertFrom-Json
    $profile = $data.profiles.$ProfileKey

    if (-not $profile) {
        $profile = $data.profiles.Fallback
    }

    return $profile
}

function Get-RIFEModelInfo {
    <#
    .SYNOPSIS
        Returns model metadata (enum name, VRAM, quality) for a given model key.
    #>
    param(
        [string]$ModelKey = "v4.25",
        [string]$ProfilesPath
    )

    if (-not $ProfilesPath) {
        $moduleDir = Split-Path $PSScriptRoot -Parent
        $ProfilesPath = Join-Path $moduleDir "profiles\gpu-profiles.json"
    }

    if (-not (Test-Path $ProfilesPath)) { return $null }

    $data = Get-Content $ProfilesPath -Raw | ConvertFrom-Json
    return $data.rife_models.$ModelKey
}

function Format-GPUInfo {
    <#
    .SYNOPSIS
        Returns a formatted string summary of GPU detection results.
    #>
    param([hashtable]$GPUEnv)

    $lines = @()
    $lines += "GPU       : $($GPUEnv.GPU)"
    if ($GPUEnv.GPUGen)        { $lines += "Generación: $($GPUEnv.GPUGen)" }
    if ($GPUEnv.ComputeCap)    { $lines += "Compute   : SM $($GPUEnv.ComputeCap)" }
    if ($GPUEnv.DriverVersion) { $lines += "Driver    : $($GPUEnv.DriverVersion)" }
    $lines += "Backend   : $($GPUEnv.SupportedBackend)"
    $lines += "Perfil    : $($GPUEnv.ProfileKey)"
    return $lines
}

Export-ModuleMember -Function Detect-GPU, Get-GPUProfile, Get-RIFEModelInfo, Format-GPUInfo
