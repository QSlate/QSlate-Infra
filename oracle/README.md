# Oracle VM (dev/staging)

One Ampere A1 VM on Oracle Cloud Always Free runs a single-node k3s cluster (Traefik built in).

| | |
|---|---|
| Region | `eu-paris-1` (home region, permanent) |
| Shape | `VM.Standard.A1.Flex`, **2 OCPU / 12 GB** (the Always Free limit since June 2026, do not go above) |
| OS | Ubuntu 26.04 LTS, arm64 |
| k3s | `v1.36.5+k3s1`, node `qslate-k3s-1` |
| Public ports | 22 only for now. 80/443 are open in the host firewall but still closed in the VCN security list |

## Files

- `cloud-init.yaml`: first-boot setup. SSH keys only and no root login, fail2ban, automatic security updates, host firewall rules for 80/443 and the k3s pod/service networks, then k3s (pinned).
- `launch-retry.sh`: creates the VM with the OCI CLI and retries while Oracle answers "Out of host capacity".

## Create a new VM

Prerequisites: OCI CLI configured (`~/.oci/config`), a public subnet, an SSH public key.

```bash
SUBNET_ID=<public subnet OCID> ./oracle/launch-retry.sh
```

Optional variables: `OCPUS` (2), `MEMORY_GB` (12), `UBUNTU_VERSION` (26.04), `INTERVAL` (60 s), `NAME`, `SSH_KEY`.
The VM runs `cloud-init.yaml` on first boot; progress is in `/var/log/cloud-init-output.log`.

The current VM was created from the console without `cloud-init.yaml`; the same steps were applied by hand over SSH on 2026-10-29.

## Check that the VM is healthy

```bash
ssh -i <key> ubuntu@<VM_PUBLIC_IP>
sudo k3s kubectl get nodes                  # qslate-k3s-1 Ready
sudo k3s kubectl get pods -A                # coredns, traefik, metrics-server, local-path: Running
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/   # 404 from Traefik (no app yet)
sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication) '   # both "no"
sudo fail2ban-client status sshd
```

## Rules

- Never resize above 2 OCPU / 12 GB: anything above is billed.
- The k3s API (6443) is never public: use an SSH tunnel (`ssh -L 6443:127.0.0.1:6443 ...`) until the VPN is set up.
- An Oracle port must be opened in **both** the VCN security list and the host firewall (`iptables`, saved with `netfilter-persistent save` before k3s adds its own rules).
- SSH private keys and the kubeconfig never go in this repo.
