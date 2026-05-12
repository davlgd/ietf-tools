#!/bin/bash
# Build a release-mode rfc binary for the current matrix entry and emit
# SHA-256 / SHA-512 checksums next to it. The runner sets OS and ARCH so
# the artefact name stays consistent across self-hosted and GitHub-hosted
# runners regardless of what `uname -s` happens to return locally.
set -euo pipefail

OS="${OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
ARCH="${ARCH:-$(uname -m | tr '[:upper:]' '[:lower:]')}"
FILE_NAME="rfc-${OS}-${ARCH}"
BIN_FOLDER="bin"

echo "Building ${FILE_NAME} on ${OS}/${ARCH}..."
mkdir -p "${BIN_FOLDER}"
v -prod . -o "${BIN_FOLDER}/${FILE_NAME}"

cd "${BIN_FOLDER}"
(shasum -a 256 "${FILE_NAME}" 2>/dev/null || sha256sum "${FILE_NAME}") > "${FILE_NAME}.sha256"
(shasum -a 512 "${FILE_NAME}" 2>/dev/null || sha512sum "${FILE_NAME}") > "${FILE_NAME}.sha512"
