#!/usr/bin/env bash

set -euo pipefail

: "${AWS_ACCESS_KEY_ID:?Set AWS_ACCESS_KEY_ID}"
: "${AWS_SECRET_ACCESS_KEY:?Set AWS_SECRET_ACCESS_KEY}"

echo "── 1/3  Installing External Secrets Operator via Helm ──────────────────"
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --wait

echo "── 2/3  Creating IAM bootstrap secret for ESO ──────────────────────────"
kubectl create secret generic aws-iam-bootstrap \
  --namespace=external-secrets \
  --from-literal=access-key-id="${AWS_ACCESS_KEY_ID}" \
  --from-literal=secret-access-key="${AWS_SECRET_ACCESS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "── 3/3  Creating qslate namespace ──────────────────────────────────────"
kubectl create namespace qslate --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Bootstrap complete. Now run: ./scripts/deploy.sh"
