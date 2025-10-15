#!/bin/sh

TAG="$1"
VERSION=$(echo $TAG | sed 's/^v//')

ARCH="amd64 arm64"
AMD64_FILENAME="nexttrace_linux_amd64"
ARM64_FILENAME="nexttrace_linux_arm64"

SIGNING_KEY_ID="${SIGNING_KEY_ID:-}"
SIGNING_KEY="${SIGNING_KEY:-}"
SIGNING_KEY_FILE="${SIGNING_KEY_FILE:-}"
SIGNING_KEY_PASSPHRASE="${SIGNING_KEY_PASSPHRASE:-}"

TMP_GNUPGHOME=""

cleanup() {
    if [ -n "$TMP_GNUPGHOME" ] && [ -d "$TMP_GNUPGHOME" ]; then
        rm -rf "$TMP_GNUPGHOME"
    fi
}

maybe_import_signing_key() {
    if [ -z "$SIGNING_KEY" ] && [ -z "$SIGNING_KEY_FILE" ]; then
        return
    fi

    TMP_GNUPGHOME=$(mktemp -d 2>/dev/null || mktemp -d -t gnupg)
    if [ ! -d "$TMP_GNUPGHOME" ]; then
        echo "Failed to create temporary GNUPGHOME directory for signing" >&2
        exit 1
    fi
    chmod 700 "$TMP_GNUPGHOME"
    export GNUPGHOME="$TMP_GNUPGHOME"
    trap cleanup EXIT

    if ! command -v gpg >/dev/null 2>&1; then
        echo "gpg command not found but signing key material was provided" >&2
        exit 1
    fi

    if [ -n "$SIGNING_KEY" ]; then
        printf '%s\n' "$SIGNING_KEY" | gpg --batch --import
    fi

    if [ -n "$SIGNING_KEY_FILE" ]; then
        gpg --batch --import "$SIGNING_KEY_FILE"
    fi
}

ensure_signing_key_id() {
    if [ -n "$SIGNING_KEY_ID" ]; then
        return
    fi

    if command -v gpg >/dev/null 2>&1; then
        SIGNING_KEY_ID=$(gpg --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: '/^sec/ { print $5; exit }')
    fi
}

sign_release() {
    if [ -z "$SIGNING_KEY_ID" ]; then
        echo "Warning: SIGNING_KEY_ID is not set; skipping Release file signing." >&2
        return
    fi

    if ! command -v gpg >/dev/null 2>&1; then
        echo "Warning: gpg command not found; skipping Release file signing." >&2
        return
    fi

    if [ -n "$SIGNING_KEY_PASSPHRASE" ]; then
        gpg --batch --yes --pinentry-mode loopback --passphrase "$SIGNING_KEY_PASSPHRASE" --local-user "$SIGNING_KEY_ID" --output Release.gpg --detach-sign Release
        gpg --batch --yes --pinentry-mode loopback --passphrase "$SIGNING_KEY_PASSPHRASE" --local-user "$SIGNING_KEY_ID" --output InRelease --clearsign Release
    else
        gpg --batch --yes --local-user "$SIGNING_KEY_ID" --output Release.gpg --detach-sign Release
        gpg --batch --yes --local-user "$SIGNING_KEY_ID" --output InRelease --clearsign Release
    fi
}

export_public_signing_key() {
    if [ -z "$SIGNING_KEY_ID" ]; then
        return
    fi

    if ! command -v gpg >/dev/null 2>&1; then
        return
    fi

    gpg --batch --yes --export "$SIGNING_KEY_ID" > nexttrace-archive-keyring.gpg
    gpg --batch --yes --armor --export "$SIGNING_KEY_ID" > nexttrace-archive-keyring.asc
}

maybe_import_signing_key
ensure_signing_key_id

get_url_by_arch() {
    case $1 in
    "amd64") echo "https://github.com/nxtrace/NTrace-core/releases/download/$TAG/$AMD64_FILENAME" ;;
    "arm64") echo "https://github.com/nxtrace/NTrace-core/releases/download/$TAG/$ARM64_FILENAME" ;;
    esac
}

build() {
    # Prepare
    BASE_DIR="nexttrace"_"$VERSION"-1_"$1"
    cp -r templates "$BASE_DIR"
    sed -i "s/Architecture: arch/Architecture: $1/" "$BASE_DIR/DEBIAN/control"
    sed -i "s/Version: version/Version: $VERSION-1/" "$BASE_DIR/DEBIAN/control"
    # Download and move file
    curl -sLo "$BASE_DIR/usr/bin/nexttrace" "$(get_url_by_arch $1)"
    chmod 755 "$BASE_DIR/usr/bin/nexttrace"
    # Build
    dpkg-deb --build --root-owner-group -Z xz "$BASE_DIR"
}

for i in $ARCH; do
    echo "Building $i package..."
    build "$i"
done

# Create repo files
apt-ftparchive packages . > Packages
apt-ftparchive release . > Release
sign_release
export_public_signing_key
