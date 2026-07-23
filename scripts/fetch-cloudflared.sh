#!/usr/bin/env bash
set -euo pipefail

TASK_FERRY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_FERRY_VERSION="2026.7.2"
TASK_FERRY_DESTINATION="$TASK_FERRY_ROOT/.vendor/cloudflared/cloudflared"
TASK_FERRY_LICENSE_DESTINATION="$TASK_FERRY_ROOT/.vendor/cloudflared/cloudflared-LICENSE"
TASK_FERRY_ARM64_SHA256="2086e51c61d6565781d84117a5007d0c826d03ffdc74acb91c08c167f9f8cd7c"
TASK_FERRY_X86_64_SHA256="4ee0d3b48a990a2f9b5faec5838f73ec1f400aa8e0a4864be576adfafec406cb"
TASK_FERRY_LICENSE_SHA256="58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd"
TASK_FERRY_UNIVERSAL_SHA256="f2d1773091c22154336f247272a48e0e4b42e550b6132755c9c2d00fc24134d8"

if [[ -x "$TASK_FERRY_DESTINATION" && -f "$TASK_FERRY_LICENSE_DESTINATION" ]]; then
  TASK_FERRY_ARCHS="$(lipo -archs "$TASK_FERRY_DESTINATION")"
  TASK_FERRY_UNIVERSAL_ACTUAL="$(shasum -a 256 "$TASK_FERRY_DESTINATION" | awk '{print $1}')"
  TASK_FERRY_LICENSE_ACTUAL="$(shasum -a 256 "$TASK_FERRY_LICENSE_DESTINATION" | awk '{print $1}')"
  if [[ "$TASK_FERRY_ARCHS" == *arm64* \
    && "$TASK_FERRY_ARCHS" == *x86_64* \
    && "$TASK_FERRY_UNIVERSAL_ACTUAL" == "$TASK_FERRY_UNIVERSAL_SHA256" \
    && "$TASK_FERRY_LICENSE_ACTUAL" == "$TASK_FERRY_LICENSE_SHA256" ]]; then
    exit 0
  fi
fi

TASK_FERRY_TEMP="$(mktemp -d)"
trap 'rm -rf "$TASK_FERRY_TEMP"' EXIT

download_and_verify() {
  local asset="$1"
  local expected="$2"
  local archive="$TASK_FERRY_TEMP/$asset"
  curl --fail --location --silent --show-error \
    "https://github.com/cloudflare/cloudflared/releases/download/$TASK_FERRY_VERSION/$asset" \
    --output "$archive"
  local actual
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "Checksum mismatch for $asset" >&2
    exit 1
  fi
  local extracted="$TASK_FERRY_TEMP/${asset%.tgz}"
  mkdir -p "$extracted"
  tar -xzf "$archive" -C "$extracted"
  printf '%s/cloudflared' "$extracted"
}

TASK_FERRY_ARM64_BINARY="$(download_and_verify cloudflared-darwin-arm64.tgz "$TASK_FERRY_ARM64_SHA256")"
TASK_FERRY_X86_64_BINARY="$(download_and_verify cloudflared-darwin-amd64.tgz "$TASK_FERRY_X86_64_SHA256")"

mkdir -p "$(dirname "$TASK_FERRY_DESTINATION")"
lipo -create \
  "$TASK_FERRY_ARM64_BINARY" \
  "$TASK_FERRY_X86_64_BINARY" \
  -output "$TASK_FERRY_DESTINATION"
chmod 755 "$TASK_FERRY_DESTINATION"

curl --fail --location --silent --show-error \
  "https://raw.githubusercontent.com/cloudflare/cloudflared/$TASK_FERRY_VERSION/LICENSE" \
  --output "$TASK_FERRY_LICENSE_DESTINATION"
TASK_FERRY_LICENSE_ACTUAL="$(shasum -a 256 "$TASK_FERRY_LICENSE_DESTINATION" | awk '{print $1}')"
[[ "$TASK_FERRY_LICENSE_ACTUAL" == "$TASK_FERRY_LICENSE_SHA256" ]] || {
  echo "Checksum mismatch for the cloudflared license" >&2
  exit 1
}

TASK_FERRY_ARCHS="$(lipo -archs "$TASK_FERRY_DESTINATION")"
TASK_FERRY_UNIVERSAL_ACTUAL="$(shasum -a 256 "$TASK_FERRY_DESTINATION" | awk '{print $1}')"
[[ "$TASK_FERRY_ARCHS" == *arm64* && "$TASK_FERRY_ARCHS" == *x86_64* ]] || {
  echo "The Cloudflare connector is not universal." >&2
  exit 1
}
[[ "$TASK_FERRY_UNIVERSAL_ACTUAL" == "$TASK_FERRY_UNIVERSAL_SHA256" ]] || {
  echo "Checksum mismatch for the universal Cloudflare connector" >&2
  exit 1
}

echo "Prepared cloudflared $TASK_FERRY_VERSION ($TASK_FERRY_ARCHS)"
