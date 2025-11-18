#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"
SOURCE_DIR="${SCRIPT_DIR}/sources"
BUILD_DIR="${SCRIPT_DIR}/build-x86_64"

WINE_VERSION="${WINE_VERSION:-9.0}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-13.0}"

ensure_rosetta() {
  if ! /usr/bin/pgrep oahd >/dev/null 2>&1; then
    echo "rosetta is required. install it with 'softwareupdate --install-rosetta'." >&2
    exit 1
  fi
}

ensure_arch_x86_64() {
  if [[ "$(arch)" != "arm64" ]]; then
    echo "this script must run on apple silicon hardware." >&2
    exit 1
  fi
}

prepare_dirs() {
  mkdir -p "${DIST_DIR}" "${SOURCE_DIR}" "${BUILD_DIR}"
}

fetch_wine() {
  local archive="wine-${WINE_VERSION}.tar.xz"
  local url="https://dl.winehq.org/wine/source/${WINE_VERSION%%.*}.x/${archive}"
  if [[ ! -f "${SOURCE_DIR}/${archive}" ]]; then
    echo "downloading wine ${WINE_VERSION}..."
    curl -L "${url}" -o "${SOURCE_DIR}/${archive}"
  fi
  if [[ ! -d "${BUILD_DIR}/wine-${WINE_VERSION}" ]]; then
    echo "extracting wine ${WINE_VERSION}..."
    tar -xf "${SOURCE_DIR}/${archive}" -C "${BUILD_DIR}"
  fi
}

install_dependencies() {
  arch -x86_64 /usr/bin/env brew bundle --file="${SCRIPT_DIR}/Brewfile"
}

configure_wine() {
  local src="${BUILD_DIR}/wine-${WINE_VERSION}"
  local build="${BUILD_DIR}/build"
  mkdir -p "${build}"
  pushd "${build}" >/dev/null
  echo "configuring wine for x86_64..."
  arch -x86_64 ../wine-"${WINE_VERSION}"/configure \
    --prefix="${DIST_DIR}/wine-x86_64-${WINE_VERSION}" \
    --enable-win64 \
    --without-oss \
    --disable-tests \
    MACOSX_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET}"
  popd >/dev/null
}

compile_wine() {
  local build="${BUILD_DIR}/build"
  pushd "${build}" >/dev/null
  echo "building wine..."
  arch -x86_64 make -j"$(sysctl -n hw.logicalcpu)"
  echo "installing wine into dist..."
  arch -x86_64 make install
  popd >/dev/null
}

package_runtime() {
  local prefix="${DIST_DIR}/wine-x86_64-${WINE_VERSION}"
  local tarball="${DIST_DIR}/wine-x86_64-${WINE_VERSION}.tar.gz"
  echo "creating ${tarball}..."
  tar -czf "${tarball}" -C "${prefix}/.." "$(basename "${prefix}")"
}

main() {
  ensure_arch_x86_64
  ensure_rosetta
  prepare_dirs
  install_dependencies
  fetch_wine
  configure_wine
  compile_wine
  package_runtime
  echo "wine runtime ready under ${DIST_DIR}."
}

main "$@"

