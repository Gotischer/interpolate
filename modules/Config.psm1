# =============================================================================
#  Config.psm1 — Configuration management
#
#  Handles: loading, saving, validation, and first-time setup of the wizard
#  configuration stored in mpv-interp-wizard.config.json.
# =============================================================================

$script:ConfigDefaults = @{
    BaseDir             = ""
    MpvConfigDir        = ""
    MpvExe              = ""
    LocalBundleDir      = ""
    # Dependency versions (auto-updated from GitHub)
    VsRelease           = "R76"
    VsReleasePrevious   = ""
    MlrtVersion         = "v15.16"
    MlrtVersionPrevious = ""
    # RIFE profile
    RifeModel           = ""          # Auto from GPU profile; v4.25_heavy, v4.25, v4.22
    RifeFp16            = $null       # Auto from GPU profile; $true/$false
    RifeStreams          = $null       # Auto from GPU profile; 1 or 2
    # Display
    DisplayDevice       = ""          # Empty = auto-detect primary
    # HDR
    HdrInterpolation    = $true       # $true = interpolate HDR; $false = Hz switch only
    # Quality
    QualityProfile      = ""          # Auto / MaxQuality / Balanced / Performance / Compat
}

function Get-ConfigFilePath {
    if ($env:MPV_INTERP_HOME -and (Test-Path $env:MPV_INTERP_HOME)) {
        return Join-Path $env:MPV_INTERP_HOME "mpv-interp-wizard.config.json"
    }
    if ($PSScriptRoot) {
        return Join-Path $PSScriptRoot "mpv-interp-wizard.config.json"
    }
    return Join-Path (Get-Location) "mpv-interp-wizard.config.json"
}

function New-WizardConfig {
    # Returns a fresh config hashtable with defaults
    return $script:ConfigDefaults.Clone()
}

function Import-WizardConfig {
    param([string]$Path)
    $config = New-WizardConfig
    if (-not $Path) { $Path = Get-ConfigFilePath }

    if (Test-Path $Path) {
        try {
            $json = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($key in @($json.PSObject.Properties.Name)) {
                if ($config.ContainsKey($key)) {
                    $config[$key] = $json.$key
                }
            }
        } catch {
            Write-Warning "Config corrupto, se usaran defaults: $_"
        }
    }
    return $config
}

function Export-WizardConfig {
    param(
        [hashtable]$Config,
        [string]$Path
    )
    if (-not $Path) { $Path = Get-ConfigFilePath }
    try {
        $dir = Split-Path $Path -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $Config | ConvertTo-Json -Depth 10 | Set-Content $Path -Encoding UTF8
        return $true
    } catch {
        Write-Warning "No se pudo guardar config: $_"
        return $false
    }
}

function Test-WizardConfig {
    # Validates that required paths are set and somewhat sane
    param([hashtable]$Config)
    $issues = @()
    if (-not $Config.MpvExe)       { $issues += "MpvExe no configurado" }
    elseif (-not (Test-Path $Config.MpvExe)) { $issues += "MpvExe no encontrado: $($Config.MpvExe)" }
    if (-not $Config.MpvConfigDir) { $issues += "MpvConfigDir no configurado" }
    if (-not $Config.BaseDir)      { $issues += "BaseDir no configurado" }
    return $issues
}

# --- Update cache (GitHub API, 24h TTL) --------------------------------------
function Get-UpdateCacheFilePath {
    param([string]$ConfigPath)
    if (-not $ConfigPath) { $ConfigPath = Get-ConfigFilePath }
    $dir = Split-Path $ConfigPath -Parent
    return Join-Path $dir "mpv-interp-wizard.update-cache.json"
}

function Get-CachedRelease {
    param([string]$Repo, [string]$CachePath)
    if (-not $CachePath) { $CachePath = Get-UpdateCacheFilePath }
    if (-not (Test-Path $CachePath)) { return $null }

    try {
        $cache = Get-Content $CachePath -Raw | ConvertFrom-Json
        $entry = $cache.$Repo
        if ($entry -and $entry.Timestamp -gt (Get-Date).AddHours(-24).Ticks -and $entry.Assets) {
            return $entry
        }
    } catch {}
    return $null
}

function Set-CachedRelease {
    param([string]$Repo, [PSCustomObject]$Release, [string]$CachePath)
    if (-not $CachePath) { $CachePath = Get-UpdateCacheFilePath }

    $cache = @{}
    if (Test-Path $CachePath) {
        try {
            $existing = Get-Content $CachePath -Raw | ConvertFrom-Json
            foreach ($prop in $existing.PSObject.Properties) {
                $cache[$prop.Name] = $prop.Value
            }
        } catch {}
    }
    $cache[$Repo] = $Release
    [PSCustomObject]$cache | ConvertTo-Json -Depth 10 | Set-Content $CachePath -Encoding UTF8
}

function Get-LatestGithubRelease {
    param([string]$Repo)
    $cached = Get-CachedRelease -Repo $Repo
    if ($cached) { return $cached }

    try {
        $apiUrl  = "https://api.github.com/repos/$Repo/releases/latest"
        $headers = @{ "Accept" = "application/vnd.github.v3+json"; "User-Agent" = "mpv-interp-wizard" }
        $json    = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 15
        if ($json) {
            $release = [PSCustomObject]@{
                Tag       = $json.tag_name
                Url       = $json.html_url
                Timestamp = (Get-Date).Ticks
                Assets    = @($json.assets | ForEach-Object {
                    [PSCustomObject]@{ Name = $_.name; Url = $_.browser_download_url; Size = $_.size }
                })
            }
            Set-CachedRelease -Repo $Repo -Release $release
            return $release
        }
    } catch {
        Write-Warning "GitHub API error for ${Repo}: $_"
    }
    return $null
}

function Compare-Versions {
    param([string]$A, [string]$B)
    if (-not $A -or -not $B) { return 0 }
    $na = ($A -replace '^[vVrR]', '')
    $nb = ($B -replace '^[vVrR]', '')
    # Pure numeric (e.g. R73 vs R76)
    if ($na -match '^\d+$' -and $nb -match '^\d+$') {
        return [math]::Sign([int]$na - [int]$nb)
    }
    try {
        $va = [version]($na -replace '[^0-9.].*$', '')
        $vb = [version]($nb -replace '[^0-9.].*$', '')
        return $va.CompareTo($vb)
    } catch {
        return [string]::Compare($na, $nb)
    }
}

# --- MPV auto-detection -------------------------------------------------------
function Find-MpvExe {
    # 1) PATH
    $w = Get-Command mpv.exe -EA SilentlyContinue
    if ($w) { return $w.Source }

    # 2) App Paths registry
    foreach ($hive in @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\mpv.exe",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\mpv.exe"
    )) {
        try {
            $v = (Get-ItemProperty -Path $hive -EA SilentlyContinue).'(default)'
            if ($v -and (Test-Path $v)) { return $v }
        } catch {}
    }

    # 3) Common locations
    $candidates = @(
        "$env:LOCALAPPDATA\mpv\mpv.exe",
        "$env:LOCALAPPDATA\Programs\mpv\mpv.exe",
        "$env:ProgramFiles\mpv\mpv.exe",
        "${env:ProgramFiles(x86)}\mpv\mpv.exe",
        "C:\mpv\mpv.exe",
        "$env:USERPROFILE\scoop\apps\mpv\current\mpv.exe",
        "$env:USERPROFILE\scoop\shims\mpv.exe",
        "C:\ProgramData\chocolatey\bin\mpv.exe"
    )
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return $null
}

function Test-MpvVapourSynth {
    param([string]$MpvExe)
    if (-not $MpvExe -or -not (Test-Path $MpvExe)) { return $false }

    $exeDir = Split-Path $MpvExe -Parent
    $com    = Join-Path $exeDir "mpv.com"
    $target = if (Test-Path $com) { $com } else { $MpvExe }

    try {
        $si = New-Object System.Diagnostics.ProcessStartInfo
        $si.FileName               = $target
        $si.Arguments              = "--version"
        $si.RedirectStandardOutput = $true
        $si.RedirectStandardError  = $true
        $si.UseShellExecute        = $false
        $si.CreateNoWindow         = $true

        $p   = [System.Diagnostics.Process]::Start($si)
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        $p.WaitForExit(3000)

        $full = $out + $err
        if ($full -match "vapoursynth") { return $true }
        # Fallback: check for DLL
        if (Test-Path (Join-Path $exeDir "vapoursynth.dll")) { return $true }
        return $false
    } catch { return $false }
}

function Find-BaseDir {
    param([string]$MpvExePath)
    $roots = [System.Collections.Generic.List[string]]::new()
    if ($MpvExePath) {
        $mpvParent = Split-Path $MpvExePath -Parent
        $grand     = Split-Path $mpvParent -Parent
        if ($mpvParent) { $roots.Add($mpvParent) }
        if ($grand)     { $roots.Add($grand) }
    }
    foreach ($d in @("C:\","D:\","E:\","F:\","G:\","H:\")) {
        if (Test-Path $d) { $roots.Add($d) }
    }
    $roots.Add("$env:LOCALAPPDATA")

    $folderNames = @("mpv-interp", "mpv-interpolation", "vapoursynth", "vs")
    foreach ($r in $roots | Select-Object -Unique) {
        foreach ($n in $folderNames) {
            $candidate = Join-Path $r $n
            $vspipe    = Join-Path $candidate "vapoursynth-portable\VSPipe.exe"
            if (Test-Path $vspipe) { return $candidate }
        }
    }
    return $null
}

function Find-PortableConfig {
    param([string]$MpvExePath)
    if (-not $MpvExePath) { return $null }
    $dir      = Split-Path $MpvExePath -Parent
    $portable = Join-Path $dir "portable_config"
    if (Test-Path $portable) { return $portable }
    # Suggest portable_config if in a "portable-looking" location
    if ($dir -match "Software|Portable|Desktop|Downloads|Games") { return $portable }
    $candidates = @((Join-Path $dir "config"), "$env:APPDATA\mpv")
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return "$env:APPDATA\mpv"
}

Export-ModuleMember -Function New-WizardConfig, Import-WizardConfig, Export-WizardConfig, `
    Test-WizardConfig, Get-ConfigFilePath, Get-LatestGithubRelease, Compare-Versions, `
    Find-MpvExe, Test-MpvVapourSynth, Find-BaseDir, Find-PortableConfig, `
    Get-UpdateCacheFilePath
