#!/usr/bin/env bash

# Enables the K3s cluster inside the existing Colima profile. It does not stop,
# recreate, or resize a running VM, so existing Docker workloads are left alone.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_deployment_config
require_command colima
resolve_kubectl

if ! colima status --profile "$COLIMA_PROFILE" >/dev/null 2>&1; then
    fail "Colima profile '${COLIMA_PROFILE}' is not running. Start it manually with the approved CPU, memory, and Kubernetes settings, then rerun this script."
fi

note "Enabling Kubernetes in Colima profile '${COLIMA_PROFILE}'..."
colima kubernetes start --profile "$COLIMA_PROFILE"

note "Waiting for the Kubernetes API..."
for _ in $(seq 1 30); do
    if kube cluster-info >/dev/null 2>&1; then
        note "Kubernetes is ready in context $(kube config current-context)."
        exit 0
    fi
    sleep 2
done

fail "Kubernetes did not become ready within 60 seconds. Run 'colima status --profile ${COLIMA_PROFILE}' and share its output with Marcopolo support."
