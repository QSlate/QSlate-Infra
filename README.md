# QSlate Infra

Kubernetes infrastructure for the QSlate platform. This repo contains all K8s manifests, Kustomize overlays, and deployment scripts. It contains **no application code** — that lives in `qslate-back` and `qslate-front`.

## Architecture Overview

```
Internet
  └── Traefik (VPS: 37.27.93.212)
        └── runner-svc (ClusterIP)
              └── runner Pod (ghcr.io/qslate/runner)
                    ├── S3 bucket (qslate-artifacts-prod-1)
                    └── K8s Job → worker Pod (ghcr.io/qslate/worker)
                                      └── S3 bucket (result upload)
```

When `POST /backtest/run` is called:
1. Runner uploads the input file to S3
2. Runner spawns a Kubernetes Job (worker)
3. Worker downloads the file, processes it, uploads the result to S3
4. Runner downloads the result and returns it to the caller

---

## Repository Structure

```
qslate-infra/
├── k8s/
│   ├── base/
│   │   └── runner-api/          # Generic K8s manifests (no env-specific values)
│   │       ├── deployment.yaml  # Runner Deployment
│   │       ├── service.yaml     # ClusterIP Service
│   │       ├── ingress.yaml     # Traefik Ingress
│   │       ├── rbac.yaml        # ServiceAccount + Role + RoleBinding
│   │       └── kustomization.yaml
│   └── overlays/
│       └── prod/                # Production-specific overrides
│           ├── externalsecrets/
│           │   └── clustersecretstore.yaml  # Connects ESO to AWS Secrets Manager
│           ├── runner-api/
│           │   ├── externalsecret.yaml      # Pulls credentials from AWS into K8s Secret
│           │   └── patch-image.yaml         # Sets real image tags
│           └── kustomization.yaml
└── scripts/
    ├── bootstrap.sh   # Run once: installs ESO + creates IAM bootstrap secret
    └── deploy.sh      # Applies the prod overlay to the cluster
```

---

## How Secrets Work

Credentials never live in this repo. The flow is:

```
AWS Secrets Manager (qslate/s3-credentials)
  └── External Secrets Operator (polls every 1h)
        └── K8s Secret "qslate-s3-secret" (auto-created in qslate namespace)
              └── Injected as env vars into runner Pod and worker Job Pods
```

The only manual secret is `aws-iam-bootstrap` (created by `bootstrap.sh`), which gives ESO permission to read from AWS Secrets Manager. Everything else is automated.

---

## Prerequisites

- k3s cluster running (Traefik included by default)
- `kubectl` configured to point at the cluster
- `helm` installed locally
- AWS account with:
  - S3 bucket (`qslate-artifacts-prod-1`)
  - IAM user (`qslate-user`) with policies:
    - `qslate-s3-policy` (S3 read/write on the bucket)
    - `qslate-secretsmanager-policy` (read `qslate/s3-credentials`)
  - Secret in AWS Secrets Manager named `qslate/s3-credentials` with keys:
    - `AWS_ACCESS_KEY_ID`
    - `AWS_SECRET_ACCESS_KEY`
    - `S3_BUCKET`
    - `AWS_REGION`

---

## First-time Setup (run once per cluster)

```bash
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

This will:
1. Install the External Secrets Operator via Helm
2. Create the `aws-iam-bootstrap` K8s secret in the `external-secrets` namespace
3. Create the `qslate` namespace

Then apply the ClusterSecretStore and ExternalSecret manually (Kustomize dry-run can't validate CRDs):
```bash
kubectl apply -f k8s/overlays/prod/externalsecrets/clustersecretstore.yaml
kubectl apply -f k8s/overlays/prod/runner-api/externalsecret.yaml
```

Verify the secret synced successfully:
```bash
kubectl get externalsecret -n qslate
# STATUS should be "SecretSynced" and READY "True"
```

---

## Deploying

```bash
# Apply base first
kubectl apply -k k8s/base/runner-api

# Apply prod overlay (image patch)
kubectl apply -k k8s/overlays/prod
```

Or use the deploy script (does a dry-run first):
```bash
./scripts/deploy.sh
```

---

## Testing

Port-forward for local testing:
```bash
kubectl port-forward svc/runner-svc 8080:80 -n qslate
echo "Hello QSlate!" | curl -X POST http://localhost:8080/backtest/run --data-binary @-
```

Through Traefik (public):
```bash
echo "Hello QSlate!" | curl -X POST http://37.27.93.212/backtest/run --data-binary @-
```

Expected response:
```
QSlate Worker Result
====================
Input file  : runs/<uuid>/input/input.txt
Byte size   : 14
Char count  : 14
```

---

## Updating After a Code Change

Images are built and pushed from `qslate-back`. After a new image is pushed to GHCR, force the cluster to pull it:

```bash
kubectl rollout restart deployment/runner -n qslate
```

---

## Team Access

### VPS (SSH)
Each team member generates their own key pair and sends their **public key** to the VPS admin:
```bash
ssh-keygen -t ed25519 -C "your@email.com"
# send ~/.ssh/id_ed25519.pub to the admin
```

Admin adds it to the VPS:
```bash
echo "ssh-ed25519 AAAA..." >> ~/.ssh/authorized_keys
```

### Kubernetes
Get the kubeconfig from the VPS and replace the internal IP with the public one:
```bash
# on the VPS
cat /etc/rancher/k3s/k3s.yaml
# replace 127.0.0.1 with 37.27.93.212
# save to ~/.kube/config on your local machine
```

### AWS
Each team member gets their own IAM user in the QSlate AWS account with the same policies as `qslate-user`. Never share credentials.

---

## Related Repos

| Repo | Role |
|---|---|
| `qslate-infra` | This repo — K8s manifests and deployment |
| `qslate-back` | Go microservices (runner, worker) + Dockerfiles |
| `qslate-front` | Next.js frontend |
