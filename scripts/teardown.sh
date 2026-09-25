#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_deployment_config
resolve_kubectl

printf 'Delete the Marcopolo POC namespace %q and all of its local data? [y/N] ' "$POC_NAMESPACE"
read -r reply
[[ "$reply" == "y" || "$reply" == "Y" ]] || {
    note "Cancelled."
    exit 0
}

kube delete namespace "$POC_NAMESPACE" --ignore-not-found
note "Deleted ${POC_NAMESPACE}."
