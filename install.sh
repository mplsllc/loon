#!/bin/sh
set -eu

# Install script for the Loon programming language.
# Usage: curl -fsSL https://loonlang.org/install.sh | sh
#
# Environment variables:
#   VERSION   - specific version to install (e.g. "0.1.0"), default: latest
#   INSTALL_DIR - override install directory

REPO="mplsllc/loon"
GITHUB_API="https://api.github.com"
GITHUB_RELEASE="https://github.com/${REPO}/releases/download"

main() {
    detect_platform
    resolve_version
    resolve_install_dir

    printf "Installing Loon %s for %s...\n" "$VERSION" "$TARGET"

    download_and_verify
    install_binary

    printf "\nLoon %s installed to %s/loon\n" "$VERSION" "$INSTALL_DIR"
    check_path
}

detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "$OS" in
        Linux)
            case "$ARCH" in
                x86_64)  TARGET="linux-x86_64" ;;
                *)       error "Unsupported architecture: $ARCH. Loon requires x86_64 on Linux." ;;
            esac
            ;;
        Darwin)
            case "$ARCH" in
                x86_64)  TARGET="macos-x86_64" ;;
                arm64)   TARGET="macos-arm64" ;;
                *)       error "Unsupported architecture: $ARCH on macOS." ;;
            esac
            ;;
        MINGW*|MSYS*|CYGWIN*|Windows_NT)
            error "Windows is not supported. Loon targets x86-64 Linux and macOS."
            ;;
        *)
            error "Unsupported operating system: $OS"
            ;;
    esac
}

resolve_version() {
    if [ -n "${VERSION:-}" ]; then
        # Strip leading 'v' if provided.
        VERSION="$(printf '%s' "$VERSION" | sed 's/^v//')"
        return
    fi

    printf "Fetching latest release...\n"

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        error "Either curl or wget is required."
    fi

    LATEST_URL="${GITHUB_API}/repos/${REPO}/releases/latest"
    if command -v curl >/dev/null 2>&1; then
        RESPONSE="$(curl -fsSL "$LATEST_URL")" || error "Failed to fetch latest release from GitHub API."
    else
        RESPONSE="$(wget -qO- "$LATEST_URL")" || error "Failed to fetch latest release from GitHub API."
    fi

    # Parse tag_name from JSON without jq.
    VERSION="$(printf '%s' "$RESPONSE" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p')"

    if [ -z "$VERSION" ]; then
        error "Could not determine latest version. Set VERSION explicitly."
    fi
}

resolve_install_dir() {
    if [ -n "${INSTALL_DIR:-}" ]; then
        return
    fi

    if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
        INSTALL_DIR="/usr/local/bin"
    elif command -v sudo >/dev/null 2>&1; then
        INSTALL_DIR="/usr/local/bin"
        NEED_SUDO=1
    else
        INSTALL_DIR="${HOME}/.local/bin"
        mkdir -p "$INSTALL_DIR"
    fi
}

download_and_verify() {
    TARBALL="loon-${TARGET}.tar.gz"
    TARBALL_URL="${GITHUB_RELEASE}/v${VERSION}/${TARBALL}"
    CHECKSUM_URL="${GITHUB_RELEASE}/v${VERSION}/${TARBALL}.sha256"

    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR"' EXIT

    printf "Downloading %s...\n" "$TARBALL"
    fetch "$TARBALL_URL" "$TMPDIR/$TARBALL"

    printf "Downloading checksum...\n"
    fetch "$CHECKSUM_URL" "$TMPDIR/${TARBALL}.sha256"

    printf "Verifying checksum...\n"
    verify_checksum "$TMPDIR" "$TARBALL"

    printf "Extracting...\n"
    tar xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"

    # The tarball contains loon-<target>/loon — find the binary.
    LOON_BIN="$(find "$TMPDIR" -name loon -type f | head -1)"
    if [ -z "$LOON_BIN" ]; then
        error "Archive does not contain a 'loon' binary."
    fi
    # Move to a predictable location for install.
    mv "$LOON_BIN" "$TMPDIR/loon"
}

fetch() {
    url="$1"
    dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$dest" "$url" || error "Download failed: $url"
    else
        wget -qO "$dest" "$url" || error "Download failed: $url"
    fi
}

verify_checksum() {
    dir="$1"
    file="$2"

    EXPECTED="$(cut -d ' ' -f 1 "$dir/${file}.sha256")"
    if [ -z "$EXPECTED" ]; then
        error "No checksum found in ${file}.sha256."
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        ACTUAL="$(sha256sum "$dir/$file" | cut -d ' ' -f 1)"
    elif command -v shasum >/dev/null 2>&1; then
        ACTUAL="$(shasum -a 256 "$dir/$file" | cut -d ' ' -f 1)"
    else
        error "No SHA-256 utility found. Install sha256sum or shasum."
    fi

    if [ "$EXPECTED" != "$ACTUAL" ]; then
        error "Checksum verification failed.
  Expected: $EXPECTED
  Actual:   $ACTUAL
This could indicate a corrupted download or a tampered release."
    fi
}

install_binary() {
    if [ "${NEED_SUDO:-0}" = "1" ]; then
        printf "Installing to %s (requires sudo)...\n" "$INSTALL_DIR"
        sudo install -m 755 "$TMPDIR/loon" "$INSTALL_DIR/loon"
    else
        install -m 755 "$TMPDIR/loon" "$INSTALL_DIR/loon"
    fi
}

check_path() {
    case ":${PATH}:" in
        *":${INSTALL_DIR}:"*) ;;
        *)
            printf "\nNote: %s is not in your PATH.\n" "$INSTALL_DIR"
            printf "Add it with:\n"
            printf "  export PATH=\"%s:\$PATH\"\n" "$INSTALL_DIR"
            ;;
    esac
}

error() {
    printf "Error: %s\n" "$1" >&2
    exit 1
}

main
