# =============================================================
# apply-branch-protection.ps1
# SOW-002 Entregable E1 — Branch protection 7 repos agt-*
# Org: clouddev-udabol
# Ramas protegidas: main, qa  |  Sin protección: dev
# =============================================================
# USO:
#   $env:GH_TOKEN = "ghp_XXXXXXXXXX"
#   .\scripts\apply-branch-protection.ps1
# =============================================================

$ORG     = "clouddev-udabol"
$REPOS   = @(
    "agt-agent",
    "agt-toolapi",
    "agt-intent-parser",
    "agt-legacy-adapter",
    "agt-whatsapp-gateway",
    "agt-readmodel",
    "agt-common"
)
$BRANCHES = @("main", "qa")

# Verificar que gh CLI está autenticado
$authCheck = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "gh CLI no autenticado. Ejecutar: `$env:GH_TOKEN = 'ghp_...'"
    exit 1
}
Write-Host "gh CLI autenticado OK" -ForegroundColor Green

# Body de protección según SOW-002 §2.1:
#   - PR obligatorio con 1 revisor
#   - Status checks CI (Lint + Unit Tests) en modo estricto
#   - No force push, no deletions
$bodyJson = @'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Lint", "Unit Tests"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
'@

$tmpFile = [System.IO.Path]::GetTempFileName() + ".json"
$bodyJson | Out-File -FilePath $tmpFile -Encoding utf8NoBOM

$errors = @()

foreach ($repo in $REPOS) {
    foreach ($branch in $BRANCHES) {
        Write-Host "`n[$repo @ $branch]" -ForegroundColor Cyan -NoNewline

        # Verificar que la rama existe antes de intentar protegerla
        $branchCheck = gh api "repos/$ORG/$repo/branches/$branch" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host " ⚠️  rama no encontrada — SALTANDO" -ForegroundColor Yellow
            $errors += "$repo @ $branch — rama no existe"
            continue
        }

        gh api "repos/$ORG/$repo/branches/$branch/protection" `
            --method PUT `
            --input $tmpFile | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Host " ✅ protección aplicada" -ForegroundColor Green
        } else {
            Write-Host " ❌ ERROR" -ForegroundColor Red
            $errors += "$repo @ $branch — fallo al aplicar protección"
        }
    }
}

Remove-Item $tmpFile -ErrorAction SilentlyContinue

# ---- Verificación final ----
Write-Host "`n===== VERIFICACIÓN E1 =====" -ForegroundColor Magenta

$results = @()
foreach ($repo in $REPOS) {
    foreach ($branch in $BRANCHES) {
        $count = gh api "repos/$ORG/$repo/branches/$branch/protection" `
            --jq '.required_pull_request_reviews.required_approving_review_count' 2>$null
        $fp    = gh api "repos/$ORG/$repo/branches/$branch/protection" `
            --jq '.allow_force_pushes.enabled' 2>$null
        $del   = gh api "repos/$ORG/$repo/branches/$branch/protection" `
            --jq '.allow_deletions.enabled' 2>$null

        $ok = ($count -eq "1") -and ($fp -eq "false") -and ($del -eq "false")
        $icon = if ($ok) { "✅" } else { "❌" }
        $results += [PSCustomObject]@{
            Repo     = $repo
            Rama     = $branch
            Revisores = $count
            ForcePush = $fp
            Borrado   = $del
            Estado    = $icon
        }
    }
}

$results | Format-Table -AutoSize

if ($errors.Count -gt 0) {
    Write-Host "`nProblemas encontrados:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
} else {
    Write-Host "`nEntregable E1 completado — branch protection activa en $($REPOS.Count) repos x $($BRANCHES.Count) ramas" -ForegroundColor Green
}
