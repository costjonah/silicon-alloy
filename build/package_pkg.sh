#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD_DIR="${PROJECT_ROOT}/build/payload"
DIST_DIR="${PROJECT_ROOT}/build/dist"
VERSION="${VERSION:-0.1.0}"
IDENTIFIER="com.siliconalloy.runtime"

clean() {
  rm -rf "${PAYLOAD_DIR}" "${DIST_DIR}"
}

prepare_payload() {
  mkdir -p "${PAYLOAD_DIR}/usr/local/share/silicon-alloy"
  mkdir -p "${DIST_DIR}"
  rsync -a "${PROJECT_ROOT}/runtime/dist/" "${PAYLOAD_DIR}/usr/local/share/silicon-alloy/runtime/"
  rsync -a "${PROJECT_ROOT}/core/target/release/" "${PAYLOAD_DIR}/usr/local/share/silicon-alloy/core/"
  rsync -a "${PROJECT_ROOT}/recipes/" "${PAYLOAD_DIR}/usr/local/share/silicon-alloy/recipes/"
  rsync -a "${PROJECT_ROOT}/gui/build/Release/SiliconAlloy.app" "${PAYLOAD_DIR}/Applications/"
}

build_pkg() {
  pkgbuild \
    --root "${PAYLOAD_DIR}" \
    --identifier "${IDENTIFIER}" \
    --version "${VERSION}" \
    --install-location "/" \
    "${DIST_DIR}/silicon-alloy-runtime.pkg"
}

notarize_pkg() {
  if [[ -z "${APPLE_NOTARIZATION_PROFILE:-}" ]]; then
    echo "skip notarization: APPLE_NOTARIZATION_PROFILE not set."
    return
  fi
  xcrun notarytool submit "${DIST_DIR}/silicon-alloy-runtime.pkg" \
    --keychain-profile "${APPLE_NOTARIZATION_PROFILE}" \
    --wait
}

main() {
  clean
  prepare_payload
  build_pkg
  notarize_pkg
  echo "pkg ready under ${DIST_DIR}."
}

main "$@"

