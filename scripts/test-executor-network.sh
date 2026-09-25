#!/usr/bin/env bash

# Tests name resolution and a TCP handshake from the same executor image and
# Kubernetes network used for customer workspaces. It never receives a
# data-source credential and creates no persistent resources.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_deployment_config
resolve_kubectl

host="${1:-}"
port="${2:-}"
[[ "$host" =~ ^[A-Za-z0-9._-]+$ ]] || fail "Usage: $0 <dns-name-or-ipv4> <tcp-port>"
[[ "$port" =~ ^[0-9]{1,5}$ ]] && (( port >= 1 && port <= 65535 )) || fail "TCP port must be between 1 and 65535"

pod_name="marcopolo-poc-network-test"
kube delete pod "$pod_name" --namespace "$POC_NAMESPACE" --ignore-not-found --wait=true >/dev/null

note "Testing DNS and TCP ${host}:${port} from the executor network..."
kube run "$pod_name" --namespace "$POC_NAMESPACE" --rm --attach --restart=Never \
    --image="$EXECUTOR_IMAGE" \
    --image-pull-policy=Never \
    --overrides='{"spec":{"serviceAccountName":"marcopolo-session"}}' \
    -- /bin/bash -lc "getent ahostsv4 '${host}' && timeout 10 bash -c '</dev/tcp/${host}/${port}' && echo 'TCP connection succeeded'"
