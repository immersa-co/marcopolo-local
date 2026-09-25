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
readonly KUBECTL_RELEASE_URL="https://api.github.com/repos/immersa-co/marcopolo-local/releases/assets/588947870"
readonly KUBECTL_RELEASE_SHA256="cf699c56340dc775230fde4ef84237d27563ea6ef52164c7d078072b586c3918"

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

github_release_token() {
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        GITHUB_RELEASE_TOKEN="$GITHUB_TOKEN"
        return
    fi

    if command -v gh >/dev/null 2>&1; then
        GITHUB_RELEASE_TOKEN="$(gh auth token 2>/dev/null || true)"
    fi

    [[ -n "${GITHUB_RELEASE_TOKEN:-}" ]] || fail "GitHub authentication is unavailable. Authenticate outside this repository before running the scripts."
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
    : "${OTEL_LGTM_IMAGE:?OTEL_LGTM_IMAGE must be set in ${RELEASE_CONFIG}}"
    : "${ALLOY_IMAGE:?ALLOY_IMAGE must be set in ${RELEASE_CONFIG}}"
    : "${MARCOPOLO_ARCHIVE_URL:?MARCOPOLO_ARCHIVE_URL must be set in ${RELEASE_CONFIG}}"
    : "${MARCOPOLO_ARCHIVE_SHA256:?MARCOPOLO_ARCHIVE_SHA256 must be set in ${RELEASE_CONFIG}}"
    : "${MPROXY_ARCHIVE_URL:?MPROXY_ARCHIVE_URL must be set in ${RELEASE_CONFIG}}"
    : "${MPROXY_ARCHIVE_SHA256:?MPROXY_ARCHIVE_SHA256 must be set in ${RELEASE_CONFIG}}"
    : "${EXECUTOR_ARCHIVE_URL:?EXECUTOR_ARCHIVE_URL must be set in ${RELEASE_CONFIG}}"
    : "${EXECUTOR_ARCHIVE_SHA256:?EXECUTOR_ARCHIVE_SHA256 must be set in ${RELEASE_CONFIG}}"
    : "${OTEL_LGTM_ARCHIVE_URL:?OTEL_LGTM_ARCHIVE_URL must be set in ${RELEASE_CONFIG}}"
    : "${OTEL_LGTM_ARCHIVE_SHA256:?OTEL_LGTM_ARCHIVE_SHA256 must be set in ${RELEASE_CONFIG}}"
    : "${ALLOY_ARCHIVE_URL:?ALLOY_ARCHIVE_URL must be set in ${RELEASE_CONFIG}}"
    : "${ALLOY_ARCHIVE_SHA256:?ALLOY_ARCHIVE_SHA256 must be set in ${RELEASE_CONFIG}}"
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

ensure_kubectl() {
    if [[ -n "${KUBECTL:-}" ]]; then
        require_command "$KUBECTL"
        export PATH="$(dirname "$KUBECTL"):${PATH}"
        return
    fi

    if command -v kubectl >/dev/null 2>&1; then
        return
    fi

    require_command curl
    require_command shasum
    github_release_token

    local tools_dir="${ROOT_DIR}/.tools"
    local kubectl_path="${tools_dir}/kubectl"
    local temporary_path="${tools_dir}/kubectl.download"
    mkdir -p "$tools_dir"

    note "Downloading kubectl from the GitHub Release..."
    curl --fail --location --proto '=https' --tlsv1.2 \
        --header 'Accept: application/octet-stream' \
        --header 'X-GitHub-Api-Version: 2022-11-28' \
        --header "Authorization: Bearer ${GITHUB_RELEASE_TOKEN}" \
        --output "$temporary_path" \
        "$KUBECTL_RELEASE_URL"
    printf '%s  %s\n' "$KUBECTL_RELEASE_SHA256" "$temporary_path" | shasum -a 256 -c -
    chmod 755 "$temporary_path"
    mv "$temporary_path" "$kubectl_path"
    export PATH="${tools_dir}:${PATH}"
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
    [[ "$url" == https://api.github.com/repos/immersa-co/marcopolo-local/releases/assets/[0-9]* ]] || {
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
        -e "s|__OTEL_LGTM_IMAGE__|${OTEL_LGTM_IMAGE//&/\\&}|g" \
        -e "s|__ALLOY_IMAGE__|${ALLOY_IMAGE//&/\\&}|g" \
        "$template"
}
