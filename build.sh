#!/usr/bin/env bash

set -Eeuo pipefail

TAG="${1:-}"
if [[ -z "${TAG}" ]]; then
    echo "Usage: $0 <tag>" >&2
    exit 1
fi

VERSION="${TAG#v}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"
OUTPUT_DIR="${SCRIPT_DIR}/output"

FLAVOR_SPECS=(
    "nexttrace|nexttrace|nexttrace|/usr/share/doc/nexttrace|NextTrace full CLI with traceroute, MTR, Globalping, and WebUI"
    "nexttrace-tiny|nexttrace-tiny|nexttrace-tiny|/usr/share/doc/nexttrace-tiny|NextTrace tiny CLI with traceroute only"
    "ntr|ntr|ntr|/usr/share/doc/ntr|NextTrace CLI focused on MTR workflows"
)

ARCH_SPECS=(
    "amd64|amd64"
    "i386|386"
    "arm64|arm64"
    "armel|armv5"
    "armhf|armv7"
    "loong64|loong64"
    "mipsel|mipsle"
    "mips64el|mips64le"
    "ppc64el|ppc64le"
    "riscv64|riscv64"
    "s390x|s390x"
)

SIGNING_KEY_ID="${SIGNING_KEY_ID:-}"
SIGNING_KEY="${SIGNING_KEY:-}"
SIGNING_KEY_FILE="${SIGNING_KEY_FILE:-}"
SIGNING_KEY_PASSPHRASE="${SIGNING_KEY_PASSPHRASE:-}"

TMP_GNUPGHOME=""
WORK_ROOT=""

cleanup() {
    if [[ -n "${WORK_ROOT}" && -d "${WORK_ROOT}" ]]; then
        rm -rf "${WORK_ROOT}"
    fi
    if [[ -n "${TMP_GNUPGHOME}" && -d "${TMP_GNUPGHOME}" ]]; then
        rm -rf "${TMP_GNUPGHOME}"
    fi
}

trap cleanup EXIT

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command not found: $1" >&2
        exit 1
    fi
}

make_temp_dir() {
    mktemp -d 2>/dev/null || mktemp -d -t nexttrace-debs
}

maybe_import_signing_key() {
    if [[ -z "${SIGNING_KEY}" && -z "${SIGNING_KEY_FILE}" ]]; then
        return
    fi

    TMP_GNUPGHOME="$(make_temp_dir)"
    if [[ ! -d "${TMP_GNUPGHOME}" ]]; then
        echo "Failed to create temporary GNUPGHOME directory for signing" >&2
        exit 1
    fi
    chmod 700 "${TMP_GNUPGHOME}"
    export GNUPGHOME="${TMP_GNUPGHOME}"

    if ! command -v gpg >/dev/null 2>&1; then
        echo "gpg command not found but signing key material was provided" >&2
        exit 1
    fi

    if [[ -n "${SIGNING_KEY}" ]]; then
        printf '%s\n' "${SIGNING_KEY}" | gpg --batch --import
    fi

    if [[ -n "${SIGNING_KEY_FILE}" ]]; then
        gpg --batch --import "${SIGNING_KEY_FILE}"
    fi
}

ensure_signing_key_id() {
    if [[ -n "${SIGNING_KEY_ID}" ]]; then
        return
    fi

    if command -v gpg >/dev/null 2>&1; then
        SIGNING_KEY_ID="$(gpg --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: '/^sec/ { print $5; exit }')"
    fi
}

sign_release() {
    if [[ -z "${SIGNING_KEY_ID}" ]]; then
        echo "Warning: SIGNING_KEY_ID is not set; skipping Release file signing." >&2
        return
    fi

    if ! command -v gpg >/dev/null 2>&1; then
        echo "Warning: gpg command not found; skipping Release file signing." >&2
        return
    fi

    if [[ -n "${SIGNING_KEY_PASSPHRASE}" ]]; then
        gpg --batch --yes --pinentry-mode loopback --passphrase "${SIGNING_KEY_PASSPHRASE}" --local-user "${SIGNING_KEY_ID}" --output Release.gpg --detach-sign Release
        gpg --batch --yes --pinentry-mode loopback --passphrase "${SIGNING_KEY_PASSPHRASE}" --local-user "${SIGNING_KEY_ID}" --output InRelease --clearsign Release
    else
        gpg --batch --yes --local-user "${SIGNING_KEY_ID}" --output Release.gpg --detach-sign Release
        gpg --batch --yes --local-user "${SIGNING_KEY_ID}" --output InRelease --clearsign Release
    fi
}

export_public_signing_key() {
    if [[ -z "${SIGNING_KEY_ID}" ]]; then
        return
    fi

    if ! command -v gpg >/dev/null 2>&1; then
        return
    fi

    gpg --batch --yes --export "${SIGNING_KEY_ID}" > nexttrace-archive-keyring.gpg
    gpg --batch --yes --armor --export "${SIGNING_KEY_ID}" > nexttrace-archive-keyring.asc
}

get_download_url() {
    local upstream_prefix="$1"
    local upstream_arch="$2"
    printf '%s\n' "https://github.com/nxtrace/NTrace-core/releases/download/${TAG}/${upstream_prefix}_linux_${upstream_arch}"
}

render_control() {
    local control_path="$1"
    local package_name="$2"
    local deb_arch="$3"
    local description="$4"

    sed -i.bak \
        -e "s/__PACKAGE__/${package_name}/g" \
        -e "s/__VERSION__/${VERSION}+1/g" \
        -e "s/__ARCHITECTURE__/${deb_arch}/g" \
        -e "s|__DESCRIPTION__|${description}|g" \
        "${control_path}"
    rm -f "${control_path}.bak"
}

prepare_layout() {
    local base_dir="$1"
    local package_name="$2"
    local binary_name="$3"
    local doc_dir="$4"
    local target_doc_dir="${base_dir}${doc_dir}"

    if [[ "${binary_name}" != "nexttrace" ]]; then
        mv "${base_dir}/usr/bin/nexttrace" "${base_dir}/usr/bin/${binary_name}"
    fi

    if [[ "${package_name}" != "nexttrace" ]]; then
        mkdir -p "$(dirname "${target_doc_dir}")"
        mv "${base_dir}/usr/share/doc/nexttrace" "${target_doc_dir}"
    fi
}

build_package() {
    local package_name="$1"
    local binary_name="$2"
    local upstream_prefix="$3"
    local doc_dir="$4"
    local description="$5"
    local deb_arch="$6"
    local upstream_arch="$7"
    local base_dir="${WORK_ROOT}/${package_name}_${VERSION}+1_${deb_arch}"
    local binary_path="${base_dir}/usr/bin/${binary_name}"
    local download_url

    download_url="$(get_download_url "${upstream_prefix}" "${upstream_arch}")"

    echo "Building ${package_name} for ${deb_arch} from ${upstream_prefix}_linux_${upstream_arch}"

    cp -R "${TEMPLATE_DIR}" "${base_dir}"
    prepare_layout "${base_dir}" "${package_name}" "${binary_name}" "${doc_dir}"
    render_control "${base_dir}/DEBIAN/control" "${package_name}" "${deb_arch}" "${description}"

    curl -fL --retry 3 --retry-delay 1 --retry-connrefused -o "${binary_path}" "${download_url}"
    chmod 755 "${binary_path}"

    dpkg-deb --build --root-owner-group -Z xz "${base_dir}" "${OUTPUT_DIR}"
}

require_command curl
require_command dpkg-deb
require_command apt-ftparchive
require_command sed

maybe_import_signing_key
ensure_signing_key_id

WORK_ROOT="$(make_temp_dir)"
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

for flavor_spec in "${FLAVOR_SPECS[@]}"; do
    IFS='|' read -r package_name binary_name upstream_prefix doc_dir description <<< "${flavor_spec}"
    for arch_spec in "${ARCH_SPECS[@]}"; do
        IFS='|' read -r deb_arch upstream_arch <<< "${arch_spec}"
        build_package "${package_name}" "${binary_name}" "${upstream_prefix}" "${doc_dir}" "${description}" "${deb_arch}" "${upstream_arch}"
    done
done

cd "${OUTPUT_DIR}"
apt-ftparchive packages . > Packages
apt-ftparchive release . > Release
sign_release
export_public_signing_key
