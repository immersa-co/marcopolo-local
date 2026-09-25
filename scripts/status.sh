#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_deployment_config
resolve_kubectl

kube get pods,services,pvc --namespace "$POC_NAMESPACE"
