#!/usr/bin/env bash

set -euo pipefail

: "${AWS_ACCESS_KEY_ID:?Set AWS_ACCESS_KEY_ID}"
: "${AWS_SECRET_ACCESS_KEY:?Set AWS_SECRET_ACCESS_KEY}"
: "${GHCR_PAT:?Set GHCR_PAT (GitHub Personal Access Token with read:packages)}"
: "${GHCR_USER:?Set GHCR_USER (GitHub username or org, e.g. qslate)}"

echo "── 1/4  Installing External Secrets Operator via Helm ──────────────────"
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --wait

echo "── 2/4  Creating IAM bootstrap secret for ESO ──────────────────────────"
kubectl create secret generic aws-iam-bootstrap \
  --namespace=external-secrets \
  --from-literal=access-key-id="${AWS_ACCESS_KEY_ID}" \
  --from-literal=secret-access-key="${AWS_SECRET_ACCESS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "── 3/4  Creating qslate namespace ──────────────────────────────────────"
kubectl create namespace qslate --dry-run=client -o yaml | kubectl apply -f -

echo "── 4/4  Creating GHCR image pull secret ────────────────────────────────"
kubectl create secret docker-registry ghcr-secret \
  --namespace=qslate \
  --docker-server=ghcr.io \
  --docker-username="${GHCR_USER}" \
  --docker-password="${GHCR_PAT}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Bootstrap complete. Now run:"
echo "  kubectl apply -f k8s/overlays/prod/externalsecrets/clustersecretstore.yaml"
echo "  kubectl apply -f k8s/overlays/prod/runner-api/externalsecret.yaml"
echo "  ./scripts/deploy.sh"
