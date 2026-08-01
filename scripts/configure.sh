#!/usr/bin/env bash
# Replaces the YOUR_GITHUB_ORG placeholder throughout the project with your real
# GitHub username/org, so you don't have to hunt down each file by hand.
#
# Usage: ./scripts/configure.sh <github-org> [repo-name]
set -euo pipefail

GITHUB_ORG="${1:?Usage: ./scripts/configure.sh <github-org> [repo-name]}"
REPO_NAME="${2:-eks-gitops}"

# Docker/GHCR image paths must be all-lowercase, even if your GitHub username/org has
# capital letters -- so image references use a lowercased copy, while the git repo URL
# keeps your org's real casing.
GITHUB_ORG_LOWER=$(echo "$GITHUB_ORG" | tr '[:upper:]' '[:lower:]')

if [ -f "argocd/application.yaml" ]; then
  sed -i.bak "s/Vishal-CloudDevOps/${GITHUB_ORG}/g; s/eks-gitops\.git/${REPO_NAME}.git/g" "argocd/application.yaml"
  rm -f "argocd/application.yaml.bak"
  echo "Updated argocd/application.yaml"
else
  echo "WARNING: not found: argocd/application.yaml (run this script from the project root)" >&2
fi

for f in "k8s/backend/deployment.yaml" "k8s/frontend/deployment.yaml"; do
  if [ -f "$f" ]; then
    sed -i.bak "s/Vishal-CloudDevOps/${GITHUB_ORG_LOWER}/g" "$f"
    rm -f "${f}.bak"
    echo "Updated $f"
  else
    echo "WARNING: not found: $f (run this script from the project root)" >&2
  fi
done

echo ""
echo "Done. Now review the diff (git diff), then:"
echo "  git add ."
echo "  git commit -m 'chore: set github org'"
echo "  git push"
