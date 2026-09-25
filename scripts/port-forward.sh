#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_deployment_config
resolve_kubectl

note "Serving Marcopolo at http://localhost:8000. Press Ctrl-C to stop this port-forward."
kube port-forward --namespace "$POC_NAMESPACE" service/mproxy 8000:8000
