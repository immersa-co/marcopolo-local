#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${ROOT_DIR}/config"
CUSTOMER_CONFIG="${CUSTOMER_CONFIG:-${CONFIG_DIR}/customer.env}"
RELEASE_CONFIG="${RELEASE_CONFIG:-${CONFIG_DIR}/release.env}"
SOPS_CONFIG_DIR="${SOPS_CONFIG_DIR:-${CONFIG_DIR}/sops}"
readonly POC_NAMESPACE="marcopolo-local"
readonly COLIMA_PROFILE="default"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

note() {
    printf '%s\n' "$*"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_file() {
    [[ -f "$1" ]] || fail "Required file not found: $1"
}

load_deployment_config() {
    require_file "$CUSTOMER_CONFIG"
    require_file "$RELEASE_CONFIG"
    source "$CUSTOMER_CONFIG"
    source "$RELEASE_CONFIG"
    : "${MARCOPOLO_IMAGE:?MARCOPOLO_IMAGE must be set in ${RELEASE_CONFIG}}"
    : "${MPROXY_IMAGE:?MPROXY_IMAGE must be set in ${RELEASE_CONFIG}}"
    : "${EXECUTOR_IMAGE:?EXECUTOR_IMAGE must be set in ${RELEASE_CONFIG}}"
    : "${MARCOPOLO_ARCHIVE_URL:?MARCOPOLO_ARCHIVE_URL must be set in ${RELEASE_CONFIG}}"
    : "${MARCOPOLO_ARCHIVE_SHA256:?MARCOPOLO_ARCHIVE_SHA256 must be set in ${RELEASE_CONFIG}}"
    : "${MPROXY_ARCHIVE_URL:?MPROXY_ARCHIVE_URL must be set in ${RELEASE_CONFIG}}"
    : "${MPROXY_ARCHIVE_SHA256:?MPROXY_ARCHIVE_SHA256 must be set in ${RELEASE_CONFIG}}"
    : "${EXECUTOR_ARCHIVE_URL:?EXECUTOR_ARCHIVE_URL must be set in ${RELEASE_CONFIG}}"
    : "${EXECUTOR_ARCHIVE_SHA256:?EXECUTOR_ARCHIVE_SHA256 must be set in ${RELEASE_CONFIG}}"
    : "${PGP_PRIVATE_KEY_FILE:?PGP_PRIVATE_KEY_FILE must be set in ${CUSTOMER_CONFIG}}"
}

resolve_kubectl() {
    if [[ -n "${KUBECTL:-}" ]]; then
        require_command "$KUBECTL"
    elif command -v kubectl >/dev/null 2>&1; then
        KUBECTL="$(command -v kubectl)"
    else
        require_command colima
        KUBECTL=""
    fi
}

kube() {
    if [[ -n "$KUBECTL" ]]; then
        "$KUBECTL" "$@"
    else
        colima ssh --profile "$COLIMA_PROFILE" -- sudo k3s kubectl "$@"
    fi
}

is_placeholder() {
    [[ "$1" == *REPLACE_WITH_* || "$1" == *'<'* || "$1" == *'>'* ]]
}

require_local_image() {
    local name="$1"
    local image="$2"
    [[ "$image" == marcopolo-poc/*:* ]] || {
        printf 'FAIL: %s must be a local marcopolo-poc image reference\n' "$name" >&2
        return 1
    }
    ! is_placeholder "$image" || {
        printf 'FAIL: %s is still a placeholder\n' "$name" >&2
        return 1
    }
}

require_release_asset() {
    local name="$1"
    local url="$2"
    local checksum="$3"
    [[ "$url" == https://github.com/*/releases/download/* ]] || {
        printf 'FAIL: %s must be a GitHub Release download URL\n' "$name" >&2
        return 1
    }
    ! is_placeholder "$url" && ! is_placeholder "$checksum" || {
        printf 'FAIL: %s is still a placeholder\n' "$name" >&2
        return 1
    }
    [[ "$checksum" =~ ^[A-Fa-f0-9]{64}$ ]] || {
        printf 'FAIL: %s must have a 64-character SHA-256 checksum\n' "$name" >&2
        return 1
    }
}

require_sops_file() {
    local name="$1"
    local path="${SOPS_CONFIG_DIR}/${name}"
    [[ -s "$path" ]] || fail "Missing required SOPS file: ${path}"
}

replace_template_values() {
    local template="$1"
    sed \
        -e "s|__NAMESPACE__|${POC_NAMESPACE}|g" \
        -e "s|__MARCOPOLO_IMAGE__|${MARCOPOLO_IMAGE//&/\\&}|g" \
        -e "s|__MPROXY_IMAGE__|${MPROXY_IMAGE//&/\\&}|g" \
        -e "s|__EXECUTOR_IMAGE__|${EXECUTOR_IMAGE//&/\\&}|g" \
        "$template"
}
