#!/usr/bin/env bash

set -euo pipefail

OVERLAY=${1:-prod}
echo "── Deploying overlay: ${OVERLAY} ───────────────────────────────────────"

kubectl apply --dry-run=server -k "k8s/overlays/${OVERLAY}"

echo ""
read -rp "Looks good? Apply for real? [y/N] " confirm
[[ "${confirm}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

kubectl apply -k "k8s/overlays/${OVERLAY}"

echo ""
echo "── Waiting for rollout ─────────────────────────────────────────────────"
kubectl rollout status deployment/runner -n qslate --timeout=120s

echo ""
echo "✓ Deployed. Test with:"
echo "  kubectl port-forward svc/runner-svc 8080:80 -n qslate"
echo "  echo 'hello' | curl -X POST http://localhost:8080/backtest/run --data-binary @-"
