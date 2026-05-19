# =============================================================================
#  Download.psm1 — Download manager with aria2 acceleration
#
#  Features: aria2 multi-connection, BITS fallback, split archives (.001/.002),
#  local cache, SHA256 verification.
# =============================================================================

function Get-7zr {
    <#
    .SYNOPSIS
        Ensures 7zr.exe is available for extracting 7z archives.
    #>
    param([string]$BaseDir)
    $z = [System.IO.Path]::GetFullPath((Join-Path $BaseDir "7zr.exe"))
    if (-not (Test-Path $z)) {
        if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir | Out-Null }
        Write-Host "     Descargando 7zr.exe..." -ForegroundColor Gray
        $oldPP = $ProgressPreference; $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -Uri "https://www.7-zip.org/a/7zr.exe" -OutFile $z -TimeoutSec 30
        $ProgressPreference = $oldPP
    }
    Unblock-File $z -EA SilentlyContinue
    return $z
}

function Get-Aria2 {
    <#
    .SYNOPSIS
        Installs aria2 for fast multi-connection downloads. Returns path or $null.
    #>
    param([string]$BaseDir)
    $binDir = Join-Path $BaseDir "bin"
    if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir | Out-Null }
    $exe = Join-Path $binDir "aria2c.exe"
    if (Test-Path $exe) { return $exe }

    Write-Host "     Instalando motor de descarga rápida (aria2)..." -ForegroundColor Gray
    $zip = Join-Path $binDir "aria2.zip"
    $url = "https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip"
    try {
        $oldPP = $ProgressPreference; $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -Uri $url -OutFile $zip -TimeoutSec 30
        $ProgressPreference = $oldPP
        Expand-Archive -Path $zip -DestinationPath $binDir -Force
        $extracted = Get-ChildItem $binDir -Filter "aria2c.exe" -Recurse | Select-Object -First 1
        if ($extracted) {
            Move-Item $extracted.FullName $exe -Force
            Remove-Item $zip -Force -EA SilentlyContinue
            # Clean up extracted subdirectory
            Get-ChildItem $binDir -Directory | Remove-Item -Recurse -Force -EA SilentlyContinue
            return $exe
        }
    } catch {
        Write-Host "[!!] No se pudo instalar aria2: $_" -ForegroundColor Yellow
    }
    return $null
}

function Invoke-Download {
    <#
    .SYNOPSIS
        Downloads a file using aria2 (fast) or BITS/WebRequest (fallback).
    .PARAMETER FileName
        Name of the file to save.
    .PARAMETER Url
        URL to download from.
    .PARAMETER BaseDir
        Directory to save the file in.
    .PARAMETER LocalBundleDir
        Optional local directory to check for pre-existing files.
    .PARAMETER ExpectedSize
        Optional expected file size for verification.
    #>
    param(
        [string]$FileName,
        [string]$Url,
        [string]$BaseDir,
        [string]$LocalBundleDir = "",
        [long]$ExpectedSize = 0
    )

    # 1) Check local bundle first
    if ($LocalBundleDir) {
        $local = Join-Path $LocalBundleDir $FileName
        if (Test-Path $local) {
            if ($ExpectedSize -eq 0 -or (Get-Item $local).Length -eq $ExpectedSize) {
                Write-Host "     Usando copia local: $local" -ForegroundColor Gray
                return $local
            }
        }
    }

    # 2) Check if already downloaded
    $dst = [System.IO.Path]::GetFullPath((Join-Path $BaseDir $FileName))
    if (Test-Path $dst) {
        if ($ExpectedSize -eq 0 -or (Get-Item $dst).Length -eq $ExpectedSize) {
            Write-Host "     Ya descargado: $FileName" -ForegroundColor Gray
            return $dst
        }
        Remove-Item $dst -Force
    }

    # Ensure target directory exists
    $targetDir = Split-Path $dst -Parent
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

    # 3) Try aria2 (16 connections)
    $aria = Get-Aria2 -BaseDir $BaseDir
    if ($aria) {
        Write-Host "     Descargando con aria2 (multi-conexión)..." -ForegroundColor Gray
        $dir  = Split-Path $dst -Parent
        $name = Split-Path $dst -Leaf
        & $aria -x 16 -s 16 -k 1M --allow-overwrite=true --auto-file-renaming=false `
            --console-log-level=warn -d $dir -o $name $Url | Out-Host
        if ($LASTEXITCODE -eq 0 -and (Test-Path $dst)) {
            if ($ExpectedSize -gt 0 -and (Get-Item $dst).Length -ne $ExpectedSize) {
                Write-Host "[!!] Tamaño incorrecto, reintentando..." -ForegroundColor Yellow
                Remove-Item $dst -Force
            } else {
                return $dst
            }
        }
        Write-Host "[!!] Aria2 falló, reintentando con método estándar..." -ForegroundColor Yellow
    }

    # 4) Fallback: BITS Transfer
    Write-Host "     Descargando $FileName (método estándar)..." -ForegroundColor Gray
    try {
        Import-Module BitsTransfer -EA SilentlyContinue
        Start-BitsTransfer -Source $Url -Destination $dst -DisplayName "Descargando $FileName"
    } catch {
        # Ultimate fallback: Invoke-WebRequest
        $oldPP = $ProgressPreference; $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -Uri $Url -OutFile $dst -TimeoutSec 300
        $ProgressPreference = $oldPP
    }

    if (-not (Test-Path $dst)) {
        throw "Failed to download $FileName"
    }
    return $dst
}

function Invoke-DownloadMultiPart {
    <#
    .SYNOPSIS
        Downloads all parts of a split archive (e.g., .7z.001, .7z.002).
    .PARAMETER BaseName
        Base filename without the part extension (e.g., "bundle.7z")
    .PARAMETER Assets
        Array of PSCustomObject with Name/Url/Size properties (from GitHub API).
    .PARAMETER BaseDir
        Directory to save files in.
    .PARAMETER LocalBundleDir
        Optional local bundle directory.
    .RETURNS
        Path to the first part (.001) for extraction.
    #>
    param(
        [string]$BaseName,
        [array]$Assets,
        [string]$BaseDir,
        [string]$LocalBundleDir = ""
    )

    # Find all parts matching the base name pattern
    $pattern = [regex]::Escape($BaseName) + "\.\d{3}$"
    $parts   = $Assets | Where-Object { $_.Name -match $pattern } | Sort-Object { $_.Name }

    if ($parts.Count -eq 0) {
        # Try single file (no split)
        $single = $Assets | Where-Object { $_.Name -eq $BaseName } | Select-Object -First 1
        if ($single) {
            return Invoke-Download -FileName $single.Name -Url $single.Url `
                -BaseDir $BaseDir -LocalBundleDir $LocalBundleDir -ExpectedSize $single.Size
        }
        throw "No assets found matching $BaseName"
    }

    Write-Host "     Archivo dividido: $($parts.Count) partes detectadas" -ForegroundColor Gray
    $firstPart = $null
    foreach ($part in $parts) {
        $path = Invoke-Download -FileName $part.Name -Url $part.Url `
            -BaseDir $BaseDir -LocalBundleDir $LocalBundleDir -ExpectedSize $part.Size
        if (-not $firstPart) { $firstPart = $path }
    }
    return $firstPart
}

function Expand-7zArchive {
    <#
    .SYNOPSIS
        Extracts a 7z archive (supports split archives) to a destination directory.
    #>
    param(
        [string]$Archive,
        [string]$DestDir,
        [string]$BaseDir
    )
    $archiveAbs = (Get-Item $Archive).FullName
    $destAbs    = [System.IO.Path]::GetFullPath($DestDir)
    if (-not (Test-Path $destAbs)) { New-Item -ItemType Directory -Path $destAbs | Out-Null }

    $z = Get-7zr -BaseDir $BaseDir
    Write-Host "     Extrayendo $([System.IO.Path]::GetFileName($archiveAbs))..." -ForegroundColor Gray

    & $z x $archiveAbs -o"$destAbs" -y -bso0 -bsp1 2>&1 | Out-Host

    if ($LASTEXITCODE -ne 0) {
        throw "7z extraction failed for $archiveAbs (exit code $LASTEXITCODE)"
    }
}

function Get-FileSHA256 {
    <#
    .SYNOPSIS
        Returns the SHA256 hash of a file as uppercase hex string.
    #>
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
}

Export-ModuleMember -Function Get-7zr, Get-Aria2, Invoke-Download, Invoke-DownloadMultiPart, `
    Expand-7zArchive, Get-FileSHA256
