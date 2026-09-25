#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_deployment_config
resolve_kubectl

component="${1:-mproxy}"
case "$component" in
    marcopolo|mproxy|otel-lgtm)
        kube logs --namespace "$POC_NAMESPACE" --follow "deployment/${component}"
        ;;
    sessions)
        kube get pods --namespace "$POC_NAMESPACE" -l app=marcopolo-user
        ;;
    *)
        fail "Usage: $0 [marcopolo|mproxy|otel-lgtm|sessions]"
        ;;
esac
