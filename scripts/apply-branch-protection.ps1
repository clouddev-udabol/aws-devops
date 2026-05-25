# =============================================================
# apply-branch-protection.ps1
# SOW-002 Entregable E1 - Branch protection 7 repos agt-*
# Org: clouddev-udabol  |  Ramas: main, qa
# =============================================================

$ORG      = "clouddev-udabol"
$REPOS    = @("agt-agent","agt-toolapi","agt-intent-parser","agt-legacy-adapter","agt-whatsapp-gateway","agt-readmodel","agt-common")
$BRANCHES = @("main","qa")

gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "gh CLI no autenticado"; exit 1 }
Write-Host "gh CLI OK - $($env:GH_TOKEN.Substring(0,8))..." -ForegroundColor Green

$errors = @()

foreach ($repo in $REPOS) {
    foreach ($branch in $BRANCHES) {
        Write-Host "`n[$repo @ $branch]" -ForegroundColor Cyan -NoNewline

        # Verificar que la rama existe
        gh api "repos/$ORG/$repo/branches/$branch" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host " SKIP - rama no encontrada" -ForegroundColor Yellow
            $errors += "$repo @ $branch - rama no existe"
            continue
        }

        # Aplicar proteccion via gh api con campos individuales
        gh api "repos/$ORG/$repo/branches/$branch/protection" `
            --method PUT `
            --header "Accept: application/vnd.github+json" `
            -F "required_status_checks[strict]=true" `
            -f "required_status_checks[contexts][]=Lint" `
            -f "required_status_checks[contexts][]=Unit Tests" `
            -F "enforce_admins=false" `
            -F "required_pull_request_reviews[required_approving_review_count]=1" `
            -F "required_pull_request_reviews[dismiss_stale_reviews]=false" `
            -F "required_pull_request_reviews[require_code_owner_reviews]=false" `
            -F "allow_force_pushes=false" `
            -F "allow_deletions=false" `
            -F "restrictions=null" 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Host " OK" -ForegroundColor Green
        } else {
            Write-Host " ERROR" -ForegroundColor Red
            $errors += "$repo @ $branch - fallo"
        }
    }
}

# Verificacion final
Write-Host "`n===== VERIFICACION E1 =====" -ForegroundColor Magenta
$results = @()
foreach ($repo in $REPOS) {
    foreach ($branch in $BRANCHES) {
        $data  = gh api "repos/$ORG/$repo/branches/$branch/protection" 2>$null | ConvertFrom-Json
        $count = if ($data) { $data.required_pull_request_reviews.required_approving_review_count } else { $null }
        $fp    = if ($data) { $data.allow_force_pushes.enabled } else { $null }
        $del   = if ($data) { $data.allow_deletions.enabled } else { $null }
        $ok    = ($count -eq 1) -and ($fp -eq $false) -and ($del -eq $false)
        $results += [PSCustomObject]@{
            Repo      = $repo
            Rama      = $branch
            Revisores = $count
            ForcePush = $fp
            Borrado   = $del
            Estado    = if ($ok) { "OK" } else { "FAIL" }
        }
    }
}
$results | Format-Table -AutoSize

if ($errors.Count -eq 0) {
    Write-Host "Entregable E1 completado OK" -ForegroundColor Green
} else {
    Write-Host "Errores:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}
