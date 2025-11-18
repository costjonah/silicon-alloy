#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../" && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
SOURCE_DIR="${SCRIPT_DIR}/sources"
BUILD_DIR="${SCRIPT_DIR}/build-arm64"

WINE_VERSION="${WINE_VERSION:-9.0}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-13.0}"

prepare_dirs() {
  mkdir -p "${DIST_DIR}" "${SOURCE_DIR}" "${BUILD_DIR}"
}

install_deps() {
  brew bundle --file="${SCRIPT_DIR}/Brewfile"
}

fetch_wine() {
  local archive="wine-${WINE_VERSION}.tar.xz"
  local url="https://dl.winehq.org/wine/source/${WINE_VERSION%%.*}.x/${archive}"
  if [[ ! -f "${SOURCE_DIR}/${archive}" ]]; then
    echo "downloading wine ${WINE_VERSION} for arm64..."
    curl -L "${url}" -o "${SOURCE_DIR}/${archive}"
  fi
  if [[ ! -d "${BUILD_DIR}/wine-${WINE_VERSION}" ]]; then
    tar -xf "${SOURCE_DIR}/${archive}" -C "${BUILD_DIR}"
  fi
}

configure() {
  local src="${BUILD_DIR}/wine-${WINE_VERSION}"
  local build="${BUILD_DIR}/build"
  mkdir -p "${build}"
  pushd "${build}" >/dev/null
  "${src}/configure" \
    --prefix="${DIST_DIR}/wine-arm64-${WINE_VERSION}" \
    --without-oss \
    --disable-tests \
    --host=arm64-apple-darwin \
    MACOSX_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET}"
  popd >/dev/null
}

compile() {
  pushd "${BUILD_DIR}/build" >/dev/null
  make -j"$(sysctl -n hw.logicalcpu)"
  make install
  popd >/dev/null
}

package() {
  local prefix="${DIST_DIR}/wine-arm64-${WINE_VERSION}"
  tar -czf "${DIST_DIR}/wine-arm64-${WINE_VERSION}.tar.gz" -C "${prefix}/.." "$(basename "${prefix}")"
}

main() {
  prepare_dirs
  install_deps
  fetch_wine
  configure
  compile
  package
  echo "arm64 wine build available under ${DIST_DIR}."
  echo "export SILICON_ALLOY_ARM64_WINE64=${DIST_DIR}/wine-arm64-${WINE_VERSION}/bin/wine64"
}

main "$@"

