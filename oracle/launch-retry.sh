#!/usr/bin/env bash
# Retry creating the QSlate A1 VM until Oracle has capacity ("Out of host capacity").
# Free tier only: VM.Standard.A1.Flex, Ubuntu (26.04 by default), 100 GB boot volume.
#
# Usage: SUBNET_ID=ocid1.subnet... ./oracle/launch-retry.sh
# Optional env: OCPUS (2), MEMORY_GB (12), INTERVAL (60 seconds), NAME (qslate-k3s-1), UBUNTU_VERSION (26.04)
# Requires: oci CLI configured (~/.oci/config), ~/.ssh/qslate_oracle.pub
set -euo pipefail

cd "$(dirname "$0")"

NAME="${NAME:-qslate-k3s-1}"
OCPUS="${OCPUS:-2}"
MEMORY_GB="${MEMORY_GB:-12}"
INTERVAL="${INTERVAL:-60}"
UBUNTU_VERSION="${UBUNTU_VERSION:-26.04}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/qslate_oracle.pub}"
: "${SUBNET_ID:?set SUBNET_ID to the public subnet OCID}"

# Read-only lookups: retry a few times (a new API key returns 401 for a few minutes)
lookup() {
    local i
    for i in $(seq 1 20); do
        if "$@" 2>/dev/null; then
            return 0
        fi
        sleep 15
    done
    echo "lookup failed: $*" >&2
    return 1
}

# Root compartment = tenancy
COMPARTMENT_ID="${COMPARTMENT_ID:-$(awk -F= '/^tenancy/ {print $2; exit}' ~/.oci/config)}"
AD="$(lookup oci iam availability-domain list --compartment-id "$COMPARTMENT_ID" \
    --query 'data[0].name' --raw-output)"
IMAGE_ID="$(lookup oci compute image list --compartment-id "$COMPARTMENT_ID" \
    --operating-system "Canonical Ubuntu" --operating-system-version "$UBUNTU_VERSION" \
    --shape VM.Standard.A1.Flex --sort-by TIMECREATED --sort-order DESC \
    --query 'data[?!contains("display-name", `Minimal`)] | [0].id' --raw-output)"

echo "AD=$AD"
echo "IMAGE=$IMAGE_ID"
echo "shape=VM.Standard.A1.Flex ${OCPUS} OCPU / ${MEMORY_GB} GB, retry every ${INTERVAL}s"

existing="$(lookup oci compute instance list --compartment-id "$COMPARTMENT_ID" \
    --display-name "$NAME" --query 'data[?"lifecycle-state"!=`TERMINATED`] | length(@)' \
    --raw-output)"
# The CLI prints nothing when the list is empty
if [ -n "$existing" ] && [ "$existing" != "0" ]; then
    echo "An instance named $NAME already exists, nothing to do."
    exit 0
fi

attempt=0
while true; do
    attempt=$((attempt + 1))
    if out="$(oci compute instance launch \
        --compartment-id "$COMPARTMENT_ID" \
        --availability-domain "$AD" \
        --display-name "$NAME" \
        --shape VM.Standard.A1.Flex \
        --shape-config "{\"ocpus\": $OCPUS, \"memoryInGBs\": $MEMORY_GB}" \
        --image-id "$IMAGE_ID" \
        --boot-volume-size-in-gbs 100 \
        --subnet-id "$SUBNET_ID" \
        --assign-public-ip true \
        --ssh-authorized-keys-file "$SSH_KEY" \
        --user-data-file cloud-init.yaml 2>&1)"; then
        echo "$(date '+%F %T') attempt $attempt: instance created"
        echo "$out" | grep -E '"(id|lifecycle-state)"' | head -2
        exit 0
    fi

    if echo "$out" | grep -qi "capacity"; then
        echo "$(date '+%F %T') attempt $attempt: out of capacity, retrying in ${INTERVAL}s"
        sleep "$INTERVAL"
    elif echo "$out" | grep -qi "TooManyRequests"; then
        echo "$(date '+%F %T') attempt $attempt: rate limited, waiting 5 min"
        sleep 300
    elif echo "$out" | grep -qiE "timed out|RequestException|ConnectionError|Max retries"; then
        # Local network drop (wifi, laptop sleep): keep going
        echo "$(date '+%F %T') attempt $attempt: network error, retrying in 2 min"
        sleep 120
    elif echo "$out" | grep -qi "NotAuthenticated"; then
        # A new API key takes a few minutes to reach every OCI service
        echo "$(date '+%F %T') attempt $attempt: not authenticated (key propagation?), retrying in 30s"
        sleep 30
    else
        echo "$(date '+%F %T') attempt $attempt: unexpected error, stopping:"
        echo "$out"
        exit 1
    fi
done
