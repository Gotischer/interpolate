# =============================================================================
#  FFmpegDetect.psm1 — Detect FFmpeg FRUC Vulkan filter availability
#
#  Checks whether the mpv build links an FFmpeg version that includes the
#  vf_fruc_vulkan filter (merged 2026-08-29). This allows the wizard to
#  offer the zero-dependency FRUC backend on supported NVIDIA GPUs.
# =============================================================================

function Test-FrucVulkanAvailable {
    <#
    .SYNOPSIS
        Returns $true if the mpv build includes the fruc_vulkan video filter.
    .PARAMETER MpvExe
        Path to mpv.exe (or mpv.com).
    .DESCRIPTION
        Runs `mpv --vf=help` and searches the output for "fruc_vulkan".
        This is the most reliable way to check because mpv statically links
        FFmpeg — there is no separate ffmpeg.exe to query.
    #>
    param([string]$MpvExe)

    if (-not $MpvExe -or -not (Test-Path $MpvExe)) { return $false }

    $exeDir = Split-Path $MpvExe -Parent
    $com    = Join-Path $exeDir "mpv.com"
    $target = if (Test-Path $com) { $com } else { $MpvExe }

    try {
        $si = New-Object System.Diagnostics.ProcessStartInfo
        $si.FileName               = $target
        $si.Arguments              = "--vf=help"
        $si.RedirectStandardOutput = $true
        $si.RedirectStandardError  = $true
        $si.UseShellExecute        = $false
        $si.CreateNoWindow         = $true

        $p   = [System.Diagnostics.Process]::Start($si)
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        if (-not $p.WaitForExit(5000)) {
            try { $p.Kill() } catch {}
            return $false
        }

        $full = $out + $err
        return ($full -match 'fruc_vulkan')
    } catch {
        return $false
    }
}

function Get-MpvFFmpegVersion {
    <#
    .SYNOPSIS
        Extracts the FFmpeg version string linked into the mpv build.
    .DESCRIPTION
        Runs `mpv --version` and parses the FFmpeg library version line.
        Returns a string like "7.1" or $null if not detected.
    #>
    param([string]$MpvExe)

    if (-not $MpvExe -or -not (Test-Path $MpvExe)) { return $null }

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
        if (-not $p.WaitForExit(3000)) {
            try { $p.Kill() } catch {}
            return $null
        }

        $full = $out + $err
        # Typical line: "ffmpeg library versions: ..." or "libavutil 59.8.100"
        if ($full -match 'ffmpeg\s+(?:library\s+)?version[s]?\s*[:\-]?\s*(\S+)') {
            return $Matches[1]
        }
        # Alternative: parse from mpv version line "mpv 0.39.0 ... FFmpeg N-..."
        if ($full -match 'FFmpeg\s+(\S+)') {
            return $Matches[1]
        }
        return $null
    } catch {
        return $null
    }
}

Export-ModuleMember -Function Test-FrucVulkanAvailable, Get-MpvFFmpegVersion
