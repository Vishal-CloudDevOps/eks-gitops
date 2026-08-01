#!/usr/bin/env bash
# Replaces the YOUR_GITHUB_ORG placeholder throughout the project with your real
# GitHub username/org, so you don't have to hunt down each file by hand.
#
# Usage: ./scripts/configure.sh <github-org> [repo-name]
set -euo pipefail

GITHUB_ORG="${1:?Usage: ./scripts/configure.sh <github-org> [repo-name]}"
REPO_NAME="${2:-eks-gitops}"

FILES=(
  "k8s/backend/deployment.yaml"
  "k8s/frontend/deployment.yaml"
  "argocd/application.yaml"
)

for f in "${FILES[@]}"; do
  if [ -f "$f" ]; then
    sed -i.bak "s/YOUR_GITHUB_ORG/${GITHUB_ORG}/g; s/eks-gitops\.git/${REPO_NAME}.git/g" "$f"
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
