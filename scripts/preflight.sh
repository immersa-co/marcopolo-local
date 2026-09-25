#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_deployment_config
require_command colima
require_command docker
resolve_kubectl

errors=0
report_error() {
    printf 'FAIL: %s\n' "$*" >&2
    errors=$((errors + 1))
}

[[ "$(uname -s)" == "Darwin" ]] || report_error "The POC release is scoped to macOS."
[[ "$(uname -m)" == "arm64" ]] || report_error "The POC release requires an Apple Silicon Mac."

if ! docker info >/dev/null 2>&1; then
    report_error "Docker CLI cannot reach the Colima engine."
fi

if ! colima status --profile "$COLIMA_PROFILE" >/dev/null 2>&1; then
    report_error "Colima profile '${COLIMA_PROFILE}' is not running."
fi

if ! kube cluster-info >/dev/null 2>&1; then
    report_error "kubectl cannot reach a Kubernetes cluster. Run ./scripts/bootstrap-kubernetes.sh after the approved Colima Kubernetes setup."
fi

for image_spec in \
    "MARCOPOLO_IMAGE:${MARCOPOLO_IMAGE}" \
    "MPROXY_IMAGE:${MPROXY_IMAGE}" \
    "EXECUTOR_IMAGE:${EXECUTOR_IMAGE}"; do
    image_name="${image_spec%%:*}"
    image_ref="${image_spec#*:}"
    if ! require_local_image "$image_name" "$image_ref"; then
        errors=$((errors + 1))
    fi
done

for asset_spec in \
    "MARCOPOLO_ARCHIVE:${MARCOPOLO_ARCHIVE_URL}:${MARCOPOLO_ARCHIVE_SHA256}" \
    "MPROXY_ARCHIVE:${MPROXY_ARCHIVE_URL}:${MPROXY_ARCHIVE_SHA256}" \
    "EXECUTOR_ARCHIVE:${EXECUTOR_ARCHIVE_URL}:${EXECUTOR_ARCHIVE_SHA256}"; do
    asset_name="${asset_spec%%:*}"
    asset_values="${asset_spec#*:}"
    asset_url="${asset_values%:*}"
    asset_checksum="${asset_values##*:}"
    if ! require_release_asset "$asset_name" "$asset_url" "$asset_checksum"; then
        errors=$((errors + 1))
    fi
done

[[ -f "$PGP_PRIVATE_KEY_FILE" ]] || report_error "PGP_PRIVATE_KEY_FILE does not point to a readable private-key export."
if [[ -f "$PGP_PRIVATE_KEY_FILE" ]]; then
    pgp_mode="$(stat -f '%Lp' "$PGP_PRIVATE_KEY_FILE" 2>/dev/null || true)"
    [[ -n "$pgp_mode" && $((8#$pgp_mode & 8#077)) -eq 0 ]] || report_error "PGP private-key export must not be group- or world-readable."
fi

if [[ -n "${PGP_PASSPHRASE_FILE:-}" ]]; then
    [[ -f "$PGP_PASSPHRASE_FILE" ]] || report_error "PGP_PASSPHRASE_FILE does not point to a readable file."
    if [[ -f "$PGP_PASSPHRASE_FILE" ]]; then
        passphrase_mode="$(stat -f '%Lp' "$PGP_PASSPHRASE_FILE" 2>/dev/null || true)"
        [[ -n "$passphrase_mode" && $((8#$passphrase_mode & 8#077)) -eq 0 ]] || report_error "PGP passphrase file must not be group- or world-readable."
    fi
fi

for sops_file in .sops.yaml mcp.secrets.yaml mproxy.secrets.yaml; do
    if [[ ! -s "${SOPS_CONFIG_DIR}/${sops_file}" ]]; then
        report_error "Missing required SOPS file: ${SOPS_CONFIG_DIR}/${sops_file}."
    elif grep -q 'REPLACE_WITH_' "${SOPS_CONFIG_DIR}/${sops_file}"; then
        report_error "${SOPS_CONFIG_DIR}/${sops_file} still has a placeholder."
    fi
done

if [[ -f "${SOPS_CONFIG_DIR}/mcp.secrets.yaml" ]] && ! grep -q '^sops:' "${SOPS_CONFIG_DIR}/mcp.secrets.yaml"; then
    report_error "mcp.secrets.yaml is not SOPS encrypted."
fi
if [[ -f "${SOPS_CONFIG_DIR}/mproxy.secrets.yaml" ]] && ! grep -q '^sops:' "${SOPS_CONFIG_DIR}/mproxy.secrets.yaml"; then
    report_error "mproxy.secrets.yaml is not SOPS encrypted."
fi

if (( errors > 0 )); then
    exit 1
fi

note "PASS: macOS arm64, Docker, Colima, Kubernetes, encrypted SOPS configuration, and GitHub Release image inputs are ready."
