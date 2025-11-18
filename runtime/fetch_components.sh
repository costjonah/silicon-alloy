#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"
CACHE_DIR="${SCRIPT_DIR}/cache"

DXVK_VERSION="${DXVK_VERSION:-2.4}"
VKD3D_VERSION="${VKD3D_VERSION:-1.10}"
GECKO_VERSION="${GECKO_VERSION:-2.47.4}"
MONO_VERSION="${MONO_VERSION:-8.1.0}"

mkdir -p "${DIST_DIR}" "${CACHE_DIR}"

download() {
  local name="$1"
  local url="$2"
  local archive="${CACHE_DIR}/${name}"
  if [[ ! -f "${archive}" ]]; then
    echo "fetching ${name}..."
    curl -L "${url}" -o "${archive}"
  else
    echo "using cached ${name}."
  fi
  echo "${archive}"
}

extract() {
  local archive="$1"
  local target_dir="$2"
  mkdir -p "${target_dir}"
  tar -xf "${archive}" -C "${target_dir}"
}

bundle_dxvk() {
  local archive
  archive=$(download "dxvk-${DXVK_VERSION}.tar.gz" "https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VERSION}/dxvk-${DXVK_VERSION}.tar.gz")
  extract "${archive}" "${DIST_DIR}"
}

bundle_vkd3d() {
  local archive
  archive=$(download "vkd3d-proton-${VKD3D_VERSION}.tar.zst" "https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v${VKD3D_VERSION}/vkd3d-proton-${VKD3D_VERSION}.tar.zst")
  if command -v zstd >/dev/null 2>&1; then
    mkdir -p "${DIST_DIR}/vkd3d"
    tar --use-compress-program=zstd -xf "${archive}" -C "${DIST_DIR}/vkd3d"
  else
    echo "install zstd to unpack vkd3d archives." >&2
  fi
}

bundle_wine_gecko() {
  download "wine-gecko-${GECKO_VERSION}-x86.msi" "https://dl.winehq.org/wine/wine-gecko/${GECKO_VERSION}/wine-gecko-${GECKO_VERSION}-x86.msi"
  download "wine-gecko-${GECKO_VERSION}-x86_64.msi" "https://dl.winehq.org/wine/wine-gecko/${GECKO_VERSION}/wine-gecko-${GECKO_VERSION}-x86_64.msi"
}

bundle_wine_mono() {
  download "wine-mono-${MONO_VERSION}.msi" "https://dl.winehq.org/wine/wine-mono/${MONO_VERSION}/wine-mono-${MONO_VERSION}.msi"
}

main() {
  bundle_dxvk
  bundle_vkd3d
  bundle_wine_gecko
  bundle_wine_mono
  echo "auxiliary components downloaded into ${DIST_DIR}."
}

main "$@"

