#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_command colima
resolve_kubectl

if ! colima status --profile "$COLIMA_PROFILE" >/dev/null 2>&1; then
    fail "Colima profile '${COLIMA_PROFILE}' is not running. Start it manually with the approved CPU, memory, and Kubernetes settings, then rerun this script."
fi

note "Starting Kubernetes in Colima profile '${COLIMA_PROFILE}'..."
colima ssh --profile "$COLIMA_PROFILE" -- sudo systemctl start k3s

note "Waiting for the Kubernetes API..."
for _ in $(seq 1 30); do
    if colima ssh --profile "$COLIMA_PROFILE" -- sudo k3s kubectl cluster-info >/dev/null 2>&1; then
        note "Kubernetes is ready in context $(kube config current-context)."
        exit 0
    fi
    sleep 2
done

fail "Kubernetes did not become ready within 60 seconds. Run 'colima status --profile ${COLIMA_PROFILE}' and share its output with Marcopolo support."
