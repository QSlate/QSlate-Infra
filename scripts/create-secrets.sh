#!/usr/bin/env bash
# Create the Secrets of one environment directly in the cluster.
# Values are generated here and passed to kubectl through file descriptors:
# nothing is written to disk, printed, or visible in the process list.
# Existing Secrets are kept as they are (no silent rotation).
#
# Usage: ./scripts/create-secrets.sh <namespace>     e.g. qslate-staging
# Needs: kubectl pointing at the cluster, openssl.
set -euo pipefail

NS="${1:?usage: $0 <namespace>}"
kubectl get namespace "$NS" >/dev/null # create it first: ./scripts/deploy.sh <env>

exists() { kubectl -n "$NS" get secret "$1" >/dev/null 2>&1; }
secret_value() { kubectl -n "$NS" get secret "$1" -o "jsonpath={.data.$2}" | base64 -d; }

# Database passwords, shared by the Postgres init script and the services.
if exists postgres; then
    auth_pw=$(secret_value postgres AUTH_DB_PASSWORD)
    workspace_pw=$(secret_value postgres WORKSPACE_DB_PASSWORD)
    echo "kept    postgres"
else
    auth_pw=$(openssl rand -hex 24)
    workspace_pw=$(openssl rand -hex 24)
    kubectl -n "$NS" create secret generic postgres --from-env-file=<(
        printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 24)"
        printf 'AUTH_DB_PASSWORD=%s\n' "$auth_pw"
        printf 'WORKSPACE_DB_PASSWORD=%s\n' "$workspace_pw"
    ) >/dev/null
    echo "created postgres"
fi

for svc in auth workspace; do
    if exists "$svc-db"; then
        echo "kept    $svc-db"
        continue
    fi
    pw_var="${svc}_pw"
    kubectl -n "$NS" create secret generic "$svc-db" --from-env-file=<(
        printf 'DATABASE_URL=postgres://%s:%s@postgres:5432/qslate_%s?sslmode=disable\n' "$svc" "${!pw_var}" "$svc"
    ) >/dev/null
    echo "created $svc-db"
done

# JWT signing key (Ed25519, PKCS#8 PEM like QSlate-Back's dev-init).
# The private key goes to auth only; gateway and workspace get the public key.
if exists auth-jwt-private; then
    echo "kept    auth-jwt-private"
    private_key=$(secret_value auth-jwt-private 'auth-private\.pem')
else
    private_key=$(openssl genpkey -algorithm ed25519)
    kubectl -n "$NS" create secret generic auth-jwt-private \
        --from-file=auth-private.pem=<(printf '%s\n' "$private_key") >/dev/null
    echo "created auth-jwt-private"
fi
# Always (re)derived from the private key, so the two can never drift apart.
kubectl -n "$NS" create secret generic auth-jwt-public \
    --from-file=auth-public.pem=<(printf '%s\n' "$private_key" | openssl pkey -pubout) \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "synced  auth-jwt-public"
