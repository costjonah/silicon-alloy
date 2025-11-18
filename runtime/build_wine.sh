#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"
SOURCE_DIR="${SCRIPT_DIR}/sources"
BUILD_DIR="${SCRIPT_DIR}/build-x86_64"

WINE_VERSION="${WINE_VERSION:-9.2}"
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
  mkdir -p "${DIST_DIR}" "${SOURCE_DIR}"
  rm -rf "${BUILD_DIR}"
  mkdir -p "${BUILD_DIR}"
}

download_wine() {
  local archive="wine-${WINE_VERSION}.tar.xz"
  local destination="${SOURCE_DIR}/${archive}"
  local major="${WINE_VERSION%%.*}"
  local urls=(
    "https://dl.winehq.org/wine/source/${major}.x/${archive}"
    "https://mirrors.kernel.org/wine/source/${major}.x/${archive}"
    "https://mirrors.ocf.berkeley.edu/wine/source/${major}.x/${archive}"
  )

  if [[ -f "${destination}" ]]; then
    local size
    size=$(stat -f%z "${destination}")
    if [[ "${size}" -lt 1048576 ]]; then
      echo "cached ${archive} looks incomplete (${size} bytes); re-downloading." >&2
      rm -f "${destination}"
    fi
  fi

  if [[ ! -f "${destination}" ]]; then
    local tmp success url
    tmp="$(mktemp)"
    success=false
    for url in "${urls[@]}"; do
      echo "downloading wine ${WINE_VERSION} from ${url}..." >&2
      if curl --fail --location --retry 3 --retry-delay 2 \
        -H "Accept: application/octet-stream" \
        -o "${tmp}" \
        "${url}"; then
        mv "${tmp}" "${destination}"
        success=true
        break
      else
        echo "failed to fetch ${archive} from ${url}" >&2
        rm -f "${tmp}" 2>/dev/null || true
        tmp="$(mktemp)"
      fi
    done
    rm -f "${tmp}" 2>/dev/null || true
    if [[ "${success}" != true ]]; then
      echo "unable to download ${archive} from known mirrors." >&2
      exit 1
    fi
  fi
}

extract_wine() {
  local archive="wine-${WINE_VERSION}.tar.xz"
  local destination="${SOURCE_DIR}/${archive}"
  if [[ ! -d "${BUILD_DIR}/wine-${WINE_VERSION}" ]]; then
    echo "extracting wine ${WINE_VERSION}..." >&2
    tar -xf "${destination}" -C "${BUILD_DIR}"
  fi
}

install_dependencies() {
  local brew_bin="${INTEL_BREW_BIN:-}"
  if [[ -z "${brew_bin}" ]]; then
    brew_bin="$(/usr/bin/env command -v brew)"
  fi
  if [[ -z "${brew_bin}" || ! -x "${brew_bin}" ]]; then
    echo "unable to locate intel homebrew binary. set INTEL_BREW_BIN to /usr/local/bin/brew." >&2
    exit 1
  fi
  typeset -g BREW_BIN="${brew_bin}"
  arch -x86_64 "${brew_bin}" bundle --file="${SCRIPT_DIR}/Brewfile"
}

setup_toolchain() {
  local brew_bin="${BREW_BIN:-}"
  if [[ -z "${brew_bin}" ]]; then
    return
  fi

  local bison_prefix
  bison_prefix="$(arch -x86_64 "${brew_bin}" --prefix bison 2>/dev/null || true)"
  if [[ -n "${bison_prefix}" && -d "${bison_prefix}/bin" ]]; then
    export PATH="${bison_prefix}/bin:${PATH}"
    export YACC="${bison_prefix}/bin/bison -y"
    export BISON_PKGDATADIR="${bison_prefix}/share/bison"
  fi

  local pkgconfig_prefix
  pkgconfig_prefix="$(arch -x86_64 "${brew_bin}" --prefix pkg-config 2>/dev/null || true)"
  if [[ -n "${pkgconfig_prefix}" && -d "${pkgconfig_prefix}/bin" ]]; then
    export PATH="${pkgconfig_prefix}/bin:${PATH}"
  fi

  local sdk_path
  sdk_path="$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  export MACOSX_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET}"
  export ac_cv_cflags__mabi_ms=no

  local common_flags="-arch x86_64 -mmacosx-version-min=${MACOS_DEPLOYMENT_TARGET}"
  if [[ -n "${sdk_path}" ]]; then
    export SDKROOT="${sdk_path}"
    common_flags="${common_flags} -isysroot ${sdk_path}"
  fi

  export CFLAGS="${common_flags}${CFLAGS:+ ${CFLAGS}}"
  export CXXFLAGS="${common_flags}${CXXFLAGS:+ ${CXXFLAGS}}"
  export OBJCFLAGS="${common_flags}${OBJCFLAGS:+ ${OBJCFLAGS}}"
  export OBJCXXFLAGS="${common_flags}${OBJCXXFLAGS:+ ${OBJCXXFLAGS}}"
  export LDFLAGS="${common_flags}${LDFLAGS:+ ${LDFLAGS}}"

  local clang_bin clangxx_bin
  clang_bin="$(/usr/bin/xcrun --sdk macosx --find clang 2>/dev/null || /usr/bin/xcrun --find clang 2>/dev/null || true)"
  clangxx_bin="$(/usr/bin/xcrun --sdk macosx --find clang++ 2>/dev/null || /usr/bin/xcrun --find clang++ 2>/dev/null || true)"
  if [[ -x "${clang_bin}" ]]; then
    export CC="${clang_bin}"
    export OBJC="${clang_bin}"
  fi
  if [[ -x "${clangxx_bin}" ]]; then
    export CXX="${clangxx_bin}"
    export OBJCXX="${clangxx_bin}"
  fi

  if [[ -z "${CC:-}" || -z "${CXX:-}" ]]; then
    local gcc_prefix
    gcc_prefix="$(arch -x86_64 "${brew_bin}" --prefix gcc 2>/dev/null || true)"
    if [[ -n "${gcc_prefix}" && -d "${gcc_prefix}/bin" ]]; then
      local gcc_version gcc_major gcc_bin gxx_bin
      gcc_version="$(arch -x86_64 "${brew_bin}" list --versions gcc 2>/dev/null | awk '{print $2}' | head -n1)"
      gcc_major="${gcc_version%%.*}"
      gcc_bin="${gcc_prefix}/bin/gcc-${gcc_major}"
      gxx_bin="${gcc_prefix}/bin/g++-${gcc_major}"
      [[ -x "${gcc_bin}" ]] || gcc_bin="${gcc_prefix}/bin/gcc"
      [[ -x "${gxx_bin}" ]] || gxx_bin="${gcc_prefix}/bin/g++"
      if [[ -x "${gcc_bin}" && -z "${CC:-}" ]]; then
        export CC="${gcc_bin}"
        export OBJC="${gcc_bin}"
        export PATH="$(dirname "${gcc_bin}"):${PATH}"
      fi
      if [[ -x "${gxx_bin}" && -z "${CXX:-}" ]]; then
        export CXX="${gxx_bin}"
        export OBJCXX="${gxx_bin}"
      fi
    fi
  fi

  export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:${PKG_CONFIG_PATH:-}"
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
  setup_toolchain
  download_wine
  extract_wine
  configure_wine
  compile_wine
  package_runtime
  echo "wine runtime ready under ${DIST_DIR}."
}

main "$@"

