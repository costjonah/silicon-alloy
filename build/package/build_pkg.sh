#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PAYLOAD_DIR="${ROOT_DIR}/build/package/payload"
PKG_DIR="${ROOT_DIR}/build/package/output"
IDENTIFIER="${PKG_IDENTIFIER:-com.siliconalloy.runtime}"
VERSION="${PKG_VERSION:-0.1.0}"

log() {
  printf "[build-pkg] %s\n" "$*" >&2
}

fail() {
  printf "[build-pkg] error: %s\n" "$*" >&2
  exit 1
}

prepare_payload() {
  rm -rf "${PAYLOAD_DIR}"
  mkdir -p "${PAYLOAD_DIR}/Library/SiliconAlloy"
  local dist_root="${ROOT_DIR}/runtime/build/dist"
  local runtime_bundle
  runtime_bundle="$(find "${dist_root}" -maxdepth 1 -type d -name 'wine-*' | head -n1 || true)"
  [[ -n "${runtime_bundle}" ]] || fail "no wine bundle found; run build_wine.sh first"
  rsync -a "${runtime_bundle}/" "${PAYLOAD_DIR}/Library/SiliconAlloy/runtime/"
}

generate_pkg() {
  mkdir -p "${PKG_DIR}"
  pkgbuild \
    --root "${PAYLOAD_DIR}" \
    --install-location "/" \
    --identifier "${IDENTIFIER}" \
    --version "${VERSION}" \
    "${PKG_DIR}/silicon-alloy-runtime-${VERSION}.pkg"
}

sign_and_notarize() {
  if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    log "skipping signing because DEVELOPER_ID_APPLICATION is not set"
    return
  fi

  local pkg="${PKG_DIR}/silicon-alloy-runtime-${VERSION}.pkg"
  productsign --sign "${DEVELOPER_ID_APPLICATION}" "${pkg}" "${pkg%.pkg}-signed.pkg"

  if [[ -n "${AC_USERNAME:-}" && -n "${AC_PASSWORD:-}" ]]; then
    xcrun notarytool submit "${pkg%.pkg}-signed.pkg" --apple-id "${AC_USERNAME}" --password "${AC_PASSWORD}" --team-id "${AC_TEAM_ID}" --wait
  else
    log "notarization credentials missing; leaving signed package unsigned with apple"
  fi
}

main() {
  prepare_payload
  generate_pkg
  sign_and_notarize
  log "package artifacts live in ${PKG_DIR}"
}

main "$@"

