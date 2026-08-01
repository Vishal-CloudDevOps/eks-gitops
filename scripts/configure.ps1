<#
.SYNOPSIS
  Replaces the YOUR_GITHUB_ORG placeholder throughout the project with your real
  GitHub username/org, so you don't have to hunt down each file by hand.

.EXAMPLE
  .\scripts\configure.ps1 -GitHubOrg "Vishal-CloudDevOps"
#>
param(
  [Parameter(Mandatory = $true)][string]$GitHubOrg,
  [string]$RepoName = "eks-gitops"
)

# Docker/GHCR image paths must be all-lowercase, even if your GitHub username/org has
# capital letters (e.g. "Vishal-CloudDevOps") -- so image references use a lowercased
# copy, while the git repo URL keeps your org's real casing (GitHub itself doesn't care
# either way, but it's clearer to read).
$GitHubOrgLower = $GitHubOrg.ToLower()

# argocd/application.yaml: git repo URL -- keep original casing
if (Test-Path "argocd/application.yaml") {
  (Get-Content "argocd/application.yaml" -Raw) `
    -replace "YOUR_GITHUB_ORG", $GitHubOrg `
    -replace "eks-gitops\.git", "$RepoName.git" |
    Set-Content "argocd/application.yaml" -NoNewline
  Write-Host "Updated argocd/application.yaml"
} else {
  Write-Warning "Not found: argocd/application.yaml (run this script from the project root)"
}

# k8s manifests: container image references -- must be lowercase
$imageFiles = @("k8s/backend/deployment.yaml", "k8s/frontend/deployment.yaml")
foreach ($f in $imageFiles) {
  if (Test-Path $f) {
    (Get-Content $f -Raw) -replace "YOUR_GITHUB_ORG", $GitHubOrgLower | Set-Content $f -NoNewline
    Write-Host "Updated $f"
  } else {
    Write-Warning "Not found: $f (run this script from the project root)"
  }
}

Write-Host ""
Write-Host "Done. Now review the diff (git diff), then:"
Write-Host "  git add ."
Write-Host "  git commit -m 'chore: set github org'"
Write-Host "  git push"
