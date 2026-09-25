#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_deployment_config
require_command curl
require_command shasum
require_command docker
require_command colima

if ! colima status --profile "$COLIMA_PROFILE" >/dev/null 2>&1; then
    fail "Colima profile '${COLIMA_PROFILE}' is not running."
fi

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/marcopolo-poc-images.XXXXXX")"
cleanup() {
    rm -rf "$temporary_dir"
}
trap cleanup EXIT

import_image() {
    local name="$1"
    local url="$2"
    local checksum="$3"
    local target_image="$4"
    local archive_path="${temporary_dir}/${name}.tar.gz"
    local load_output source_image
    local curl_args=(--fail --location --proto '=https' --tlsv1.2)

    if [[ "$url" == https://api.github.com/repos/immersa-co/marcopolo-local/releases/assets/[0-9]* ]]; then
        github_release_token
        curl_args+=(--header "Accept: application/octet-stream")
        curl_args+=(--header "X-GitHub-Api-Version: 2022-11-28")
        curl_args+=(--header "Authorization: Bearer ${GITHUB_RELEASE_TOKEN}")
    fi

    note "Downloading ${name} from GitHub Release..."
    curl "${curl_args[@]}" --output "$archive_path" "$url"
    printf '%s  %s\n' "$checksum" "$archive_path" | shasum -a 256 -c -

    load_output="$(docker image load --input "$archive_path")"
    source_image="$(sed -n 's/^Loaded image: //p' <<<"$load_output" | tail -n 1)"
    if [[ -z "$source_image" ]]; then
        source_image="$(sed -n 's/^Loaded image ID: //p' <<<"$load_output" | tail -n 1)"
    fi
    [[ -n "$source_image" ]] || fail "${name} archive did not provide an image name or ID."

    docker image tag "$source_image" "$target_image"
    note "Importing ${target_image} into K3s..."
    docker image save "$target_image" | colima ssh --profile "$COLIMA_PROFILE" -- sudo k3s ctr images import -
}

import_image "marcopolo-api" "$MARCOPOLO_ARCHIVE_URL" "$MARCOPOLO_ARCHIVE_SHA256" "$MARCOPOLO_IMAGE"
import_image "mproxy" "$MPROXY_ARCHIVE_URL" "$MPROXY_ARCHIVE_SHA256" "$MPROXY_IMAGE"
import_image "marcopolo-user" "$EXECUTOR_ARCHIVE_URL" "$EXECUTOR_ARCHIVE_SHA256" "$EXECUTOR_IMAGE"

note "Imported all Marcopolo release images into K3s."
