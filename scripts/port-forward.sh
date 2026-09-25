#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_deployment_config
resolve_kubectl

grafana_log="${TMPDIR:-/tmp}/marcopolo-local-grafana-port-forward.log"

forward_grafana() {
    while true; do
        kube port-forward --namespace "$POC_NAMESPACE" service/otel-lgtm 3000:3000 >>"$grafana_log" 2>&1 || true
        sleep 2
    done
}

forward_grafana &
grafana_pid=$!
cleanup() {
    kill "$grafana_pid" 2>/dev/null || true
    wait "$grafana_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

note "Serving Marcopolo at http://localhost:8000 and Grafana at http://localhost:3000. Press Ctrl-C to stop port-forwards."
kube port-forward --namespace "$POC_NAMESPACE" service/mproxy 8000:8000
