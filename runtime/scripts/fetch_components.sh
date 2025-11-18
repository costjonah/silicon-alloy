#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CACHE_DIR="${ROOT_DIR}/runtime/cache"
DXVK_VERSION="${DXVK_VERSION:-2.4}"
VKD3D_VERSION="${VKD3D_VERSION:-1.11}"
FONTS_ARCHIVE_URL="https://sourceforge.net/projects/corefonts/files/the%20fonts/final/corefonts.exe/download"

log() {
  printf "[fetch-components] %s\n" "$*" >&2
}

fetch() {
  local url="$1"
  local dest="$2"
  if [[ -f "${dest}" ]]; then
    log "already have $(basename "${dest}")"
    return
  fi
  log "grabbing $(basename "${dest}")"
  curl -L "${url}" -o "${dest}"
}

gather_dxvk() {
  local tarball="${CACHE_DIR}/dxvk-${DXVK_VERSION}.tar.gz"
  local url="https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VERSION}/dxvk-${DXVK_VERSION}.tar.gz"
  fetch "${url}" "${tarball}"
}

gather_vkd3d() {
  local tarball="${CACHE_DIR}/vkd3d-proton-${VKD3D_VERSION}.tar.zst"
  local url="https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v${VKD3D_VERSION}/vkd3d-proton-${VKD3D_VERSION}.tar.zst"
  fetch "${url}" "${tarball}"
}

gather_fonts() {
  local dest="${CACHE_DIR}/corefonts.exe"
  fetch "${FONTS_ARCHIVE_URL}" "${dest}"
}

stage_manifest() {
  local manifest="${CACHE_DIR}/manifest.toml"
  cat >"${manifest}" <<EOF
# this file documents which helper payloads we cached locally.

[dxvk]
version = "${DXVK_VERSION}"
url = "https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VERSION}/dxvk-${DXVK_VERSION}.tar.gz"

[vkd3d]
version = "${VKD3D_VERSION}"
url = "https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v${VKD3D_VERSION}/vkd3d-proton-${VKD3D_VERSION}.tar.zst"

[corefonts]
url = "${FONTS_ARCHIVE_URL}"
EOF
}

main() {
  mkdir -p "${CACHE_DIR}"
  gather_dxvk
  gather_vkd3d
  gather_fonts
  stage_manifest
  log "cached helper payloads under ${CACHE_DIR}"
}

main "$@"

