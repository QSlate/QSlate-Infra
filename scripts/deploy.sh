#!/usr/bin/env bash
# Deploy one environment with explicit image tags (commit SHAs), never "latest".
#
# Usage:
#   BACK_TAG=<QSlate-Back SHA> FRONT_TAG=<QSlate-Front SHA> ./scripts/deploy.sh <env> [--dry-run]
#   <env> is a directory of k8s/overlays (e.g. staging).
#   --dry-run asks the API server to validate everything without changing anything
#   (the namespace must already exist).
# Needs: kubectl pointing at the cluster.
set -euo pipefail

ENV="${1:?usage: BACK_TAG=... FRONT_TAG=... $0 <env> [--dry-run]}"
MODE="${2:-}"
: "${BACK_TAG:?set BACK_TAG to the QSlate-Back commit SHA}"
: "${FRONT_TAG:?set FRONT_TAG to the QSlate-Front commit SHA}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="$ROOT/k8s/overlays/$ENV"
[ -f "$OVERLAY/kustomization.yaml" ] || { echo "no overlay: $OVERLAY" >&2; exit 1; }
NS="$(awk '/^namespace:/ {print $2}' "$OVERLAY/kustomization.yaml")"

echo "context:   $(kubectl config current-context)"
echo "namespace: $NS"
echo "back:      $BACK_TAG"
echo "front:     $FRONT_TAG"

# A throwaway kustomization on top of the overlay that only sets the tags.
# Created next to the overlays so the relative path works on Linux and macOS.
tmp="$(mktemp -d "$ROOT/k8s/.deploy.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../overlays/$ENV
images:
  - {name: ghcr.io/qslate/gateway, newTag: "$BACK_TAG"}
  - {name: ghcr.io/qslate/auth, newTag: "$BACK_TAG"}
  - {name: ghcr.io/qslate/workspace, newTag: "$BACK_TAG"}
  - {name: ghcr.io/qslate/frontend, newTag: "$FRONT_TAG"}
EOF

if [ "$MODE" = "--dry-run" ]; then
    kubectl apply --dry-run=server -k "$tmp"
    exit 0
fi

kubectl apply -k "$tmp"
kubectl -n "$NS" rollout status statefulset/postgres --timeout=300s
for d in auth workspace gateway frontend; do
    kubectl -n "$NS" rollout status "deployment/$d" --timeout=300s
done
