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

$files = @(
  "k8s/backend/deployment.yaml",
  "k8s/frontend/deployment.yaml",
  "argocd/application.yaml"
)

foreach ($f in $files) {
  if (Test-Path $f) {
    (Get-Content $f -Raw) `
      -replace "YOUR_GITHUB_ORG", $GitHubOrg `
      -replace "eks-gitops\.git", "$RepoName.git" |
      Set-Content $f -NoNewline
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
