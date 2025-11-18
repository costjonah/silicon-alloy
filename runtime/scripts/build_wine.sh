#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_ROOT="${ROOT_DIR}/runtime/build"
SRC_ROOT="${BUILD_ROOT}/src"
PATCH_DIR="${ROOT_DIR}/runtime/patches"
DIST_DIR="${BUILD_ROOT}/dist"

WINE_VERSION="${WINE_VERSION:-9.0}"
WINE_TARBALL="wine-${WINE_VERSION}.tar.xz"
WINE_URL="https://dl.winehq.org/wine/source/${WINE_VERSION%%.*}.0/${WINE_TARBALL}"

ARCH="x86_64"
MACOS_SDK_PATH="${MACOS_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)}"
MACOS_SDK_VERSION="${MACOS_SDK_VERSION:-$(xcrun --sdk macosx --show-sdk-platform-path 2>/dev/null | sed -E 's#.*/MacOSX([0-9.]+)\\.sdk#\\1#' || true)}"
MACOS_MIN_VERSION="${MACOS_MIN_VERSION:-11.0}"

log() {
  printf "[build-wine] %s\n" "$*" >&2
}

fail() {
  printf "[build-wine] error: %s\n" "$*" >&2
  exit 1
}

ensure_prereqs() {
  log "making sure we are on apple silicon and rosetta is ready"
  if [[ "$(uname -m)" != "arm64" ]]; then
    fail "this workflow expects to run on apple silicon hardware"
  fi
  if ! /usr/bin/pgrep -q oahd; then
    fail "rosetta 2 does not seem active; install it with 'softwareupdate --install-rosetta'"
  fi

  local deps=(
    autoconf automake bison gettext pkg-config gnutls libtool
    mingw-w64 nasm ninja sdl2 freetype little-cms2
  )

  for dep in "${deps[@]}"; do
    if ! brew list "$dep" >/dev/null 2>&1; then
      log "installing brew dependency: $dep"
      brew install "$dep"
    fi
  done
}

prepare_layout() {
  log "setting up build directories under ${BUILD_ROOT}"
  mkdir -p "${SRC_ROOT}" "${DIST_DIR}"
}

fetch_wine() {
  local tarball="${BUILD_ROOT}/${WINE_TARBALL}"
  if [[ ! -f "${tarball}" ]]; then
    log "downloading wine ${WINE_VERSION}"
    curl -L "${WINE_URL}" -o "${tarball}"
  else
    log "reusing cached tarball ${tarball}"
  fi

  if [[ ! -d "${SRC_ROOT}/wine-${WINE_VERSION}" ]]; then
    log "unpacking wine sources"
    tar -xf "${tarball}" -C "${SRC_ROOT}"
  else
    log "wine source directory already exists, skipping untar"
  fi
}

apply_patches() {
  local src="${SRC_ROOT}/wine-${WINE_VERSION}"
  if [[ ! -d "${PATCH_DIR}" ]]; then
    log "no patch directory found, skipping patch step"
    return
  fi

  shopt -s nullglob
  local patches=("${PATCH_DIR}/"*.patch)
  if [[ "${#patches[@]}" -eq 0 ]]; then
    log "no patches present, nothing to apply"
    return
  fi

  log "applying patches"
  for patch in "${patches[@]}"; do
    log "applying $(basename "${patch}")"
    (cd "${src}" && patch -p1 <"${patch}")
  done
}

configure_build() {
  local src="${SRC_ROOT}/wine-${WINE_VERSION}"
  local build_dir="${BUILD_ROOT}/wine-${WINE_VERSION}-${ARCH}"
  mkdir -p "${build_dir}"

  local flags=(
    "CFLAGS=-mmacosx-version-min=${MACOS_MIN_VERSION}"
    "LDFLAGS=-mmacosx-version-min=${MACOS_MIN_VERSION}"
  )

  log "configuring wine for ${ARCH}"
  local configure_args=(
    "--prefix=${DIST_DIR}/wine-${WINE_VERSION}-${ARCH}"
    "--disable-win16"
    "--enable-win64"
    "--without-oss"
    "--without-alsa"
    "--without-capi"
    "--without-gettext"
    "--without-gphoto"
    "--without-gsm"
    "--without-gstreamer"
    "--without-hal"
    "--without-krb5"
    "--without-mingw"
    "--without-opencl"
    "--without-sane"
    "--without-v4l"
    "--host=${ARCH}-apple-darwin"
  )
  if [[ -n "${MACOS_SDK_PATH}" ]]; then
    configure_args+=("--with-macos-sdk=${MACOS_SDK_PATH}")
  fi

  (
    cd "${build_dir}"
    env "${flags[@]}" \
      arch -x86_64 "${src}/configure" "${configure_args[@]}"
  )
}

build_wine() {
  local build_dir="${BUILD_ROOT}/wine-${WINE_VERSION}-${ARCH}"
  log "kicking off the build (this will take a while)"
  arch -x86_64 make -C "${build_dir}" -j"$(sysctl -n hw.logicalcpu)"
  log "installing into ${DIST_DIR}"
  arch -x86_64 make -C "${build_dir}" install
}

stage_metadata() {
  local dest="${DIST_DIR}/wine-${WINE_VERSION}-${ARCH}"
  mkdir -p "${dest}/share/silicon-alloy"

  cat >"${dest}/share/silicon-alloy/BUILDINFO" <<EOF
version=${WINE_VERSION}
arch=${ARCH}
built_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
sdk_path=${MACOS_SDK_PATH}
sdk_version=${MACOS_SDK_VERSION}
min_macos=${MACOS_MIN_VERSION}
EOF
}

main() {
  ensure_prereqs
  prepare_layout
  fetch_wine
  apply_patches
  configure_build
  build_wine
  stage_metadata
  log "wine ${WINE_VERSION} (${ARCH}) is staged under ${DIST_DIR}"
}

main "$@"

