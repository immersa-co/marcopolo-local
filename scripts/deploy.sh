#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_deployment_config
resolve_kubectl
require_command openssl
"${SCRIPT_DIR}/preflight.sh"
"${SCRIPT_DIR}/import-release-images.sh"

pgp_secret="marcopolo-poc-pgp"
sops_configmap="marcopolo-poc-sops"
sops_tools_configmap="marcopolo-poc-sops-tools"
local_auth_configmap="marcopolo-local-auth"
local_session_secret="marcopolo-local-session"
local_auth_email="${LOCAL_AUTH_EMAIL:-developer@local.marcopolo}"
[[ "$local_auth_email" =~ ^[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$ ]] \
    || fail "LOCAL_AUTH_EMAIL must be a company email address."

note "Applying namespace and local configuration..."
kube create namespace "$POC_NAMESPACE" --dry-run=client -o yaml | kube apply -f -
if [[ -z "$(kube get secret "$local_session_secret" --namespace "$POC_NAMESPACE" -o 'jsonpath={.data.session-secret}' 2>/dev/null || true)" ]]; then
    session_secret="$(openssl rand -hex 32)"
    kube create secret generic "$local_session_secret" \
        --namespace "$POC_NAMESPACE" \
        --from-literal=session-secret="$session_secret" \
        --dry-run=client -o yaml | kube apply -f -
fi
kube create configmap "$local_auth_configmap" \
    --namespace "$POC_NAMESPACE" \
    --from-literal=email="$local_auth_email" \
    --dry-run=client -o yaml | kube apply -f -
pgp_secret_args=(
    --namespace "$POC_NAMESPACE"
    --from-file=private.asc="$PGP_PRIVATE_KEY_FILE"
)
if [[ -n "${PGP_PASSPHRASE_FILE:-}" ]]; then
    pgp_secret_args+=(--from-file=passphrase="$PGP_PASSPHRASE_FILE")
else
    pgp_secret_args+=(--from-literal=passphrase=)
fi
kube create secret generic "$pgp_secret" "${pgp_secret_args[@]}" --dry-run=client -o yaml | kube apply -f -
kube create configmap "$sops_configmap" \
    --namespace "$POC_NAMESPACE" \
    --from-file=.sops.yaml="${SOPS_CONFIG_DIR}/.sops.yaml" \
    --from-file=mcp.secrets.yaml="${SOPS_CONFIG_DIR}/mcp.secrets.yaml" \
    --from-file=mproxy.secrets.yaml="${SOPS_CONFIG_DIR}/mproxy.secrets.yaml" \
    --dry-run=client -o yaml | kube apply -f -
kube create configmap "$sops_tools_configmap" \
    --namespace "$POC_NAMESPACE" \
    --from-file=sops-gpg="${ROOT_DIR}/sops-gpg" \
    --dry-run=client -o yaml | kube apply -f -

replace_template_values "${ROOT_DIR}/manifests/stack.yaml" | kube apply -f -
kube rollout restart deployment/marcopolo deployment/mproxy --namespace "$POC_NAMESPACE"

note "Waiting for local observability..."
kube rollout status deployment/otel-lgtm --namespace "$POC_NAMESPACE" --timeout=180s
kube rollout status daemonset/marcopolo-log-scraper --namespace "$POC_NAMESPACE" --timeout=180s

note "Waiting for Marcopolo and its proxy..."
kube rollout status deployment/marcopolo --namespace "$POC_NAMESPACE" --timeout=180s
kube rollout status deployment/mproxy --namespace "$POC_NAMESPACE" --timeout=180s

note "Deployed. In a separate terminal run: ./scripts/port-forward.sh"
