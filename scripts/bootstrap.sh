#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

log() {
  echo "[bootstrap] $*"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing dependency: $1" >&2
    return 1
  fi
}

ensure_rust() {
  if command -v cargo >/dev/null 2>&1; then
    return
  fi
  log "cargo not found. installing rust toolchain via rustup..."
  if ! command -v rustup >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  else
    rustup update
  fi
  if [[ -f "${HOME}/.cargo/env" ]]; then
    # shellcheck disable=SC1090
    source "${HOME}/.cargo/env"
  fi
  if ! command -v cargo >/dev/null 2>&1; then
    echo "cargo installation failed; please install rust manually (https://rustup.rs)." >&2
    exit 1
  fi
}

ensure_jq() {
  if command -v jq >/dev/null 2>&1; then
    return
  fi
  log "jq not found. installing via homebrew..."
  brew install jq
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq installation failed; please install it manually." >&2
    exit 1
  fi
}

find_intel_brew() {
  for candidate in "/usr/local/bin/brew" "/usr/local/Homebrew/bin/brew"; do
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

ensure_intel_brew() {
  local candidate
  if candidate="$(find_intel_brew)"; then
    typeset -g INTEL_BREW_BIN="${candidate}"
    log "found x86_64 homebrew at ${INTEL_BREW_BIN}"
    return
  fi
  log "x86_64 homebrew not found. installing under /usr/local (requires sudo)."
  NONINTERACTIVE=1 arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if candidate="$(find_intel_brew)"; then
    typeset -g INTEL_BREW_BIN="${candidate}"
    log "x86_64 homebrew installed at ${INTEL_BREW_BIN}"
  else
    echo "failed to install x86_64 homebrew in /usr/local. please install it manually and rerun." >&2
    exit 1
  fi
}

if [[ "$(arch)" != "arm64" ]]; then
  echo "bootstrap expects to run on apple silicon hardware." >&2
  exit 1
fi

log "checking prerequisites"
if ! require_command brew; then
  echo "homebrew is required. install from https://brew.sh and rerun." >&2
  exit 1
fi

ensure_rust

if ! require_command swift; then
  echo "swift toolchain not found. install xcode or the standalone toolchain." >&2
  exit 1
fi

ensure_jq

ensure_intel_brew

if ! /usr/bin/pgrep oahd >/dev/null 2>&1; then
  log "rosetta not detected, installing..."
  softwareupdate --install-rosetta --agree-to-license
fi

log "installing brew dependencies (x86_64)"
arch -x86_64 "${INTEL_BREW_BIN}" bundle --file="${ROOT_DIR}/runtime/Brewfile"

if ! command -v zstd >/dev/null 2>&1; then
  log "zstd not found. installing via arm64 homebrew..."
  brew install zstd
fi

log "downloading auxiliary components"
"${ROOT_DIR}/runtime/fetch_components.sh"

log "building wine runtime"
INTEL_BREW_BIN="${INTEL_BREW_BIN}" "${ROOT_DIR}/runtime/build_wine.sh"

log "building rust workspace"
cd "${ROOT_DIR}/core"
cargo build --release

log "building swift gui (release)"
cd "${ROOT_DIR}/gui"
swift build -c release

log "bootstrap complete. artifacts live under:"
echo "  - runtime dist: ${ROOT_DIR}/runtime/dist"
echo "  - daemon/cli:   ${ROOT_DIR}/core/target/release"
echo "  - gui app:      ${ROOT_DIR}/gui/.build/release/SiliconAlloyApp"

