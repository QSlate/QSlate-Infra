# QSlate Infra

Kubernetes infrastructure for QSlate: the Oracle VM, the k3s manifests and the deploy scripts.
No application code here: it lives in [QSlate-Back](https://github.com/QSlate/QSlate-Back) (Go services) and [QSlate-Front](https://github.com/QSlate/QSlate-Front) (Next.js).

## Architecture

One Oracle Cloud Always Free VM (Ampere A1, arm64, 2 OCPU / 12 GB) runs a single-node k3s cluster.

```
Browser
  └── Traefik (built into k3s, ports 80/443)
        ├── /            → frontend  (Next.js, :3000)
        └── /qslate/v1/* → gateway   (Go: JWT, CORS, rate limit, routes.json, :8080)
                              ├── auth       (Go, :8080) ──┐
                              └── workspace  (Go, :8080) ──┴── postgres (one server, one database per service)
```

- Only Traefik is reachable from the internet. Everything else is a ClusterIP Service.
- In each environment, NetworkPolicies deny all traffic, then allow only the paths above (see `k8s/base/networkpolicies.yaml`).
- Every pod runs as non-root, read-only filesystem, no capabilities, seccomp `RuntimeDefault`. The namespace enforces Pod Security `restricted`.
- Images are tagged with the git commit SHA, never `latest`.

Backtests (one Kubernetes Job per run, launched by the runner) are not deployed yet: they need the worker image from the back team.

## Layout

```
oracle/                  VM creation (OCI CLI) and first-boot setup (cloud-init), see oracle/README.md
k8s/base/                every component, without environment-specific values
k8s/overlays/staging/    namespace qslate-staging, quota, mailpit, environment ConfigMap
scripts/create-secrets.sh  generates an environment's Secrets in the cluster (nothing on disk)
scripts/deploy.sh          deploys an overlay with explicit image tags
```

## Environments

| Env | Namespace | Deployed | Data |
|---|---|---|---|
| local | your machine (Docker Compose in QSlate-Back, or k3d) | on demand | fixtures |
| staging | `qslate-staging` on the Oracle VM | from `main` | fake data only |
| prod | `qslate-prod` on the same VM (later) | on a release tag, after approval | beta users |

## Access

You need the VM's SSH key from the infra owner. Never commit or share keys or the kubeconfig.

```bash
# Shell on the VM
ssh -i ~/.ssh/<vm key> ubuntu@<VM_PUBLIC_IP>

# kubectl from your machine: the k3s API (6443) is never public, go through SSH
ssh -i ~/.ssh/<vm key> -f -N -L 16443:127.0.0.1:6443 ubuntu@<VM_PUBLIC_IP>
export KUBECONFIG=~/.kube/qslate-oracle.yaml   # server: https://127.0.0.1:16443
kubectl get nodes

# Staging in your browser (no domain yet): http://localhost:8080
ssh -i ~/.ssh/<vm key> -f -N -L 8080:127.0.0.1:80 ubuntu@<VM_PUBLIC_IP>
```

## Deploy an environment

First time only, create the namespace and its Secrets:

```bash
kubectl apply -f k8s/overlays/staging/namespace.yaml
./scripts/create-secrets.sh qslate-staging
```

Then, for every deploy (tags = commit SHAs of the images on GHCR):

```bash
BACK_TAG=<QSlate-Back SHA> FRONT_TAG=<QSlate-Front SHA> ./scripts/deploy.sh staging --dry-run
BACK_TAG=<QSlate-Back SHA> FRONT_TAG=<QSlate-Front SHA> ./scripts/deploy.sh staging
```

`--dry-run` makes the API server validate everything without changing anything. Without it, the script applies the overlay and waits for every rollout.

Useful commands:

```bash
kubectl -n qslate-staging get pods
kubectl -n qslate-staging logs deploy/gateway -f
kubectl -n qslate-staging port-forward svc/mailpit 8025   # emails sent by auth, http://localhost:8025
```

## Secrets

Secrets are never in this repo. `scripts/create-secrets.sh` generates them directly in the cluster:

| Secret | Used by | Content |
|---|---|---|
| `postgres` | postgres | superuser password, one password per service role |
| `auth-db`, `workspace-db` | auth, workspace | `DATABASE_URL` |
| `auth-jwt-private` | auth only | Ed25519 private key that signs the JWTs |
| `auth-jwt-public` | gateway, workspace | matching public key |

The script never overwrites an existing Secret. Rotation is a deliberate, documented operation (to be written in `docs/runbook.md`).

## Not done yet

- Images: QSlate-Back's CI does not publish `gateway`, `auth`, `workspace` (amd64 + arm64) yet, and QSlate-Front's image does not build (`output: "standalone"` missing in `next.config.ts`, and the API URL must become same-origin).
- Domain and HTTPS. Until then, staging is only reachable through the SSH tunnel and the VCN security list only opens port 22.
- Runner, worker image and backtest Jobs, object storage.
- Backups, monitoring, VPN for team access, prod overlay.

## Related repos

- [QSlate-Back](https://github.com/QSlate/QSlate-Back): Go gateway and services, Python backtest engine.
- [QSlate-Front](https://github.com/QSlate/QSlate-Front): Next.js dashboard.
