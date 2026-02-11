#!/usr/bin/env bash
set -euo pipefail

REGISTRY="ghcr.io/fuchs-eule"
IMAGE="rustfs-cors-patched"
BUILDER_NAME="rustfs-builder"

NO_CACHE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-cache) NO_CACHE="--no-cache" ; shift ;;
    *) echo "Unknown option: $1" >&2 ; echo "Usage: $0 [--no-cache]" >&2 ; exit 1 ;;
  esac
done

# --- Platform check ---
ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
  echo "Error: This script is designed to run on an Apple Silicon Mac (arm64)." >&2
  echo "Detected architecture: $ARCH" >&2
  exit 1
fi

# --- Docker check ---
if ! docker info &>/dev/null; then
  echo "Error: Docker is not running." >&2
  exit 1
fi
echo "Tip: For faster amd64 builds, enable Rosetta in Docker Desktop:"
echo "  Settings > General > \"Use Rosetta for x86_64/amd64 emulation on Apple Silicon\""

# --- Parse RUSTFS_VERSION from Dockerfile ---
VERSION="$(grep -E '^ARG RUSTFS_VERSION=' Dockerfile | head -1 | cut -d= -f2)"
if [[ -z "$VERSION" ]]; then
  echo "Error: Could not parse RUSTFS_VERSION from Dockerfile." >&2
  exit 1
fi
echo "RustFS version: $VERSION"

# --- GHCR authentication ---
echo "Authenticating to ghcr.io..."
GH_USER="$(gh api user --jq .login)"
gh auth token | docker login ghcr.io -u "$GH_USER" --password-stdin

# --- Ensure buildx builder exists ---
if ! docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
  echo "Creating buildx builder: $BUILDER_NAME"
  docker buildx create --name "$BUILDER_NAME" --use
else
  docker buildx use "$BUILDER_NAME"
fi

# --- Build and push ---
TAGS=(
  "--tag" "$REGISTRY/$IMAGE:latest"
  "--tag" "$REGISTRY/$IMAGE:$VERSION"
)

echo "Building and pushing: $REGISTRY/$IMAGE:latest, $REGISTRY/$IMAGE:$VERSION"
echo "Platforms: linux/amd64, linux/arm64"

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  "${TAGS[@]}" \
  $NO_CACHE \
  --push \
  .

echo ""
echo "Pushed:"
echo "  $REGISTRY/$IMAGE:latest"
echo "  $REGISTRY/$IMAGE:$VERSION"
