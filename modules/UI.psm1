# =============================================================================
#  UI.psm1 — Terminal UI helpers
#
#  Provides: colored output, arrow-key menus (PS7+), numeric fallback,
#  path prompts, and pause/continue helpers.
# =============================================================================

# --- Colored output -----------------------------------------------------------
function Write-Title($Text)   { Write-Host "`n  $Text`n" -ForegroundColor White -BackgroundColor DarkBlue }
function Write-Section($Text) { Write-Host "`n===> $Text" -ForegroundColor Cyan }
function Write-Info($Text)    { Write-Host "     $Text" -ForegroundColor Gray }
function Write-Ok($Text)      { Write-Host "[OK] $Text" -ForegroundColor Green }
function Write-Warn($Text)    { Write-Host "[!!] $Text" -ForegroundColor Yellow }
function Write-Bad($Text)     { Write-Host "[XX] $Text" -ForegroundColor Red }
function Write-Hint($Text)    { Write-Host "     $Text" -ForegroundColor DarkGray }

# --- Menu (arrows or numeric) ------------------------------------------------
function Show-Menu {
    param(
        [string]$Title,
        [string[]]$Options,
        [string]$Footer = ""
    )
    # Try arrow-key TUI; fallback to numeric
    try   { return Show-MenuArrows -Title $Title -Options $Options -Footer $Footer }
    catch { return Show-MenuNumeric -Title $Title -Options $Options -Footer $Footer }
}

function Show-MenuArrows {
    param([string]$Title, [string[]]$Options, [string]$Footer)
    $idx = 0
    $orig = $Host.UI.RawUI.CursorPosition
    while ($true) {
        $Host.UI.RawUI.CursorPosition = $orig
        Write-Host (" " * 80) -NoNewline; Write-Host ""
        Write-Host "  $Title" -ForegroundColor White -BackgroundColor DarkBlue
        Write-Host ""
        for ($i = 0; $i -lt $Options.Count; $i++) {
            if ($i -eq $idx) {
                Write-Host ("  > " + $Options[$i]) -ForegroundColor Black -BackgroundColor Cyan
            } else {
                Write-Host ("    " + $Options[$i]) -ForegroundColor Gray
            }
        }
        if ($Footer) {
            Write-Host ""
            Write-Host "  $Footer" -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-Host "  Flechas para mover, Enter para elegir, Q/Esc para cancelar" -ForegroundColor DarkGray

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($key.VirtualKeyCode) {
            38 { if ($idx -gt 0) { $idx-- } }                    # Up
            40 { if ($idx -lt $Options.Count - 1) { $idx++ } }   # Down
            13 { Clear-Host; return $idx }                        # Enter
            27 { Clear-Host; return -1 }                          # Escape
            81 { Clear-Host; return -1 }                          # Q
        }
    }
}

function Show-MenuNumeric {
    param([string]$Title, [string[]]$Options, [string]$Footer)
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ""
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $Options[$i]) -ForegroundColor Gray
    }
    if ($Footer) { Write-Host ""; Write-Host "  $Footer" -ForegroundColor DarkGray }
    Write-Host ""
    while ($true) {
        $r = Read-Host "  Elegir (1-$($Options.Count), Q para cancelar)"
        if ($r -eq "q" -or $r -eq "Q") { return -1 }
        $n = 0
        if ([int]::TryParse($r, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) {
            return ($n - 1)
        }
        Write-Warn "Opcion invalida"
    }
}

# --- Path prompt --------------------------------------------------------------
function Read-PathPrompt {
    param(
        [string]$Label,
        [string]$Default,
        [bool]$MustExist = $false,
        [bool]$AllowEmpty = $false
    )
    while ($true) {
        $shown = if ($Default) { " [$Default]" } else { "" }
        $r = Read-Host "  $Label$shown"
        if ([string]::IsNullOrWhiteSpace($r)) { $r = $Default }
        if ([string]::IsNullOrWhiteSpace($r)) {
            if ($AllowEmpty) { return "" }
            Write-Warn "Ruta requerida"; continue
        }
        if ($MustExist -and -not (Test-Path $r)) {
            $c = Read-Host "  '$r' no existe. Usar de todas formas? (s/n)"
            if ($c -ne "s" -and $c -ne "S") { continue }
        }
        return $r
    }
}

# --- Helpers ------------------------------------------------------------------
function Wait-Continue {
    Write-Host ""
    Write-Host "  Presiona Enter para volver al menu..." -ForegroundColor DarkGray
    [void](Read-Host)
}

function Show-ProgressBar {
    param([string]$Activity, [int]$PercentComplete, [string]$Status = "")
    Write-Progress -Activity $Activity -PercentComplete $PercentComplete -Status $Status
}

Export-ModuleMember -Function Write-Title, Write-Section, Write-Info, Write-Ok, Write-Warn, `
    Write-Bad, Write-Hint, Show-Menu, Read-PathPrompt, Wait-Continue, Show-ProgressBar
