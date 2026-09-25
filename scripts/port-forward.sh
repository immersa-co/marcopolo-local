#!/usr/bin/env bash

# Keeps the customer-facing endpoint on localhost. Ctrl-C stops only this
# forward; the Kubernetes workload remains running.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_deployment_config
resolve_kubectl

note "Serving Marcopolo at ${WEB_BASE_URL}. Press Ctrl-C to stop this port-forward."
kube port-forward --namespace "$POC_NAMESPACE" service/mproxy 8000:8000
