#!/bin/sh

TAG="$1"
VERSION=$(echo $TAG | sed 's/^v//')

ARCH="amd64 arm64"
AMD64_FILENAME="nexttrace_linux_amd64"
ARM64_FILENAME="nexttrace_linux_arm64"

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
    dpkg-deb --build --root-owner-group "$BASE_DIR"
}

for i in $ARCH; do
    echo "Building $i package..."
    build "$i"
done

# Create repo files
apt-ftparchive packages . > Packages
apt-ftparchive release . > Release
