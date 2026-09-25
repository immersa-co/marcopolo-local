#!/usr/bin/env bash

# Deploys only the Marcopolo POC namespace. Release images are imported into
# K3s locally and state is kept in K3s's local-path volume inside Colima.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_deployment_config
resolve_kubectl
"${SCRIPT_DIR}/preflight.sh"
"${SCRIPT_DIR}/import-release-images.sh"

pgp_secret="marcopolo-poc-pgp"
tenant_seed_configmap="marcopolo-poc-tenant-seed"
sops_configmap="marcopolo-poc-sops"
sops_tools_configmap="marcopolo-poc-sops-tools"

note "Applying namespace and local configuration..."
kube create namespace "$POC_NAMESPACE" --dry-run=client -o yaml | kube apply -f -
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
kube create configmap "$tenant_seed_configmap" \
    --namespace "$POC_NAMESPACE" \
    --from-file=seed_tenant.py="${ROOT_DIR}/manifests/seed_tenant.py" \
    --dry-run=client -o yaml | kube apply -f -
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

note "Waiting for Marcopolo and its proxy..."
kube rollout status deployment/marcopolo --namespace "$POC_NAMESPACE" --timeout=180s
kube rollout status deployment/mproxy --namespace "$POC_NAMESPACE" --timeout=180s

note "Deployed. In a separate terminal run: ./scripts/port-forward.sh"
