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
echo "── Waiting for rollouts ────────────────────────────────────────────────"
kubectl rollout status deployment/runner   -n qslate --timeout=120s
kubectl rollout status deployment/backend  -n qslate --timeout=120s
kubectl rollout status deployment/frontend -n qslate --timeout=120s

echo ""
echo "✓ Deployed. Services available at http://37.27.93.212"
echo "  Frontend : http://37.27.93.212/"
echo "  Backend  : http://37.27.93.212/api/"
echo "  Runner   : http://37.27.93.212/backtest/"
