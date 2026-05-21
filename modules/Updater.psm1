# =============================================================================
#  Updater.psm1 — Auto-update for wizard and components
#
#  Checks GitHub for newer versions of: wizard, VapourSynth, vs-mlrt.
#  Shows notifications and allows selective updates.
# =============================================================================

function Test-Updates {
    <#
    .SYNOPSIS
        Checks for updates to the wizard and its dependencies.
    .RETURNS
        Array of update info objects.
    #>
    param(
        [string]$CurrentWizardVersion,
        [hashtable]$Config
    )

    $updates = @()

    Write-Host "`n===> Buscando actualizaciones" -ForegroundColor Cyan

    # 1) Wizard
    $wizardRel = Get-LatestGithubRelease -Repo "Gotischer/interpolate"
    if ($wizardRel) {
        $cmp = Compare-Versions -A $CurrentWizardVersion -B $wizardRel.Tag
        if ($cmp -lt 0) {
            $updates += @{
                Component = "Wizard"
                Current   = "v$CurrentWizardVersion"
                Latest    = $wizardRel.Tag
                Url       = $wizardRel.Url
            }
            Write-Host "     Wizard: v$CurrentWizardVersion → $($wizardRel.Tag) (nueva versión!)" -ForegroundColor Yellow
        } else {
            Write-Host "     Wizard: v$CurrentWizardVersion (al día)" -ForegroundColor Gray
        }
    }

    # 2) VapourSynth
    $vsRel = Get-LatestGithubRelease -Repo "vapoursynth/vapoursynth"
    if ($vsRel) {
        $cmp = Compare-Versions -A $Config.VsRelease -B $vsRel.Tag
        if ($cmp -lt 0) {
            $updates += @{
                Component = "VapourSynth"
                Current   = $Config.VsRelease
                Latest    = $vsRel.Tag
                Url       = $vsRel.Url
            }
            Write-Host "     VapourSynth: $($Config.VsRelease) → $($vsRel.Tag) (nueva versión!)" -ForegroundColor Yellow
        } else {
            Write-Host "     VapourSynth: $($Config.VsRelease) (al día)" -ForegroundColor Gray
        }
    }

    # 3) vs-mlrt
    $mlrtRel = Get-LatestGithubRelease -Repo "AmusementClub/vs-mlrt"
    if ($mlrtRel) {
        $cmp = Compare-Versions -A $Config.MlrtVersion -B $mlrtRel.Tag
        if ($cmp -lt 0) {
            $updates += @{
                Component = "vs-mlrt"
                Current   = $Config.MlrtVersion
                Latest    = $mlrtRel.Tag
                Url       = $mlrtRel.Url
            }
            Write-Host "     vs-mlrt: $($Config.MlrtVersion) → $($mlrtRel.Tag) (nueva versión!)" -ForegroundColor Yellow
        } else {
            Write-Host "     vs-mlrt: $($Config.MlrtVersion) (al día)" -ForegroundColor Gray
        }
    }

    if ($updates.Count -eq 0) {
        Write-Host "[OK] Todo está al día" -ForegroundColor Green
    } else {
        Write-Host "[!!] $($updates.Count) actualización(es) disponible(s)" -ForegroundColor Yellow
    }

    return $updates
}

function Show-UpdateNotifications {
    <#
    .SYNOPSIS
        Shows update notifications in the main menu footer.
    #>
    param([array]$Updates)

    if ($Updates.Count -eq 0) { return "" }

    $parts = @()
    foreach ($u in $Updates) {
        $parts += "$($u.Component) $($u.Latest)"
    }
    return "Actualizaciones: " + ($parts -join ", ")
}

Export-ModuleMember -Function Test-Updates, Show-UpdateNotifications
