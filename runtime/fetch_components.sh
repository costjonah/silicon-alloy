#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"
CACHE_DIR="${SCRIPT_DIR}/cache"

DXVK_VERSION="${DXVK_VERSION:-2.4}"
VKD3D_VERSION="${VKD3D_VERSION:-2.12}"
GECKO_VERSION="${GECKO_VERSION:-2.47.4}"
MONO_VERSION="${MONO_VERSION:-8.1.0}"

mkdir -p "${DIST_DIR}" "${CACHE_DIR}"

download() {
  local name="$1"
  local url="$2"
  local archive="${CACHE_DIR}/${name}"
  if [[ -f "${archive}" ]]; then
    local size
    size=$(stat -f%z "${archive}")
    if [[ "${size}" -lt 1024 ]]; then
      echo "cached ${name} looks incomplete (${size} bytes); re-downloading." >&2
      rm -f "${archive}"
    else
      echo "using cached ${name}." >&2
      echo "${archive}"
      return
    fi
  fi
  echo "fetching ${name}..." >&2
  local tmp_file
  tmp_file="$(mktemp)"
  curl --fail --location --retry 3 --retry-delay 2 \
    -H "Accept: application/octet-stream" \
    -o "${tmp_file}" \
    "${url}"
  mv "${tmp_file}" "${archive}"
  echo "${archive}"
}

download_with_fallback() {
  local name="$1"
  shift
  local urls=("$@")
  local archive="${CACHE_DIR}/${name}"
  rm -f "${archive}" 2>/dev/null || true
  for url in "${urls[@]}"; do
    if download "${name}" "${url}" >/dev/null 2>&1; then
      echo "${CACHE_DIR}/${name}"
      return 0
    fi
    echo "failed to fetch ${name} from ${url}" >&2
    rm -f "${CACHE_DIR}/${name}" 2>/dev/null || true
  done
  return 1
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
    tmp_dir="$(mktemp -d)"
    tmp_tar="${tmp_dir}/vkd3d-proton.tar"
    zstd -d --force --stdout "${archive}" > "${tmp_tar}"
    tar -xf "${tmp_tar}" -C "${tmp_dir}"
    # move extracted directory into dist (handles varying top-level folder names)
    find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d '' dir; do
      rsync -a "${dir}/" "${DIST_DIR}/vkd3d/"
    done
    rm -rf "${tmp_dir}"
  else
    echo "install zstd to unpack vkd3d archives." >&2
  fi
}

bundle_wine_gecko() {
  download "wine-gecko-${GECKO_VERSION}-x86.msi" "https://dl.winehq.org/wine/wine-gecko/${GECKO_VERSION}/wine-gecko-${GECKO_VERSION}-x86.msi"
  download "wine-gecko-${GECKO_VERSION}-x86_64.msi" "https://dl.winehq.org/wine/wine-gecko/${GECKO_VERSION}/wine-gecko-${GECKO_VERSION}-x86_64.msi"
}

bundle_wine_mono() {
  local archive
  if ! archive=$(download_with_fallback \
    "wine-mono-${MONO_VERSION}.msi" \
    "https://download.winehq.org/wine/wine-mono/${MONO_VERSION}/wine-mono-${MONO_VERSION}.msi" \
    "https://github.com/madewokherd/wine-mono/releases/download/wine-mono-${MONO_VERSION}/wine-mono-${MONO_VERSION}.msi"); then
    echo "failed to download wine-mono ${MONO_VERSION} from all sources" >&2
    exit 1
  fi
  echo "${archive}" >/dev/null
}

main() {
  bundle_dxvk
  bundle_vkd3d
  bundle_wine_gecko
  bundle_wine_mono
  echo "auxiliary components downloaded into ${DIST_DIR}."
}

main "$@"

