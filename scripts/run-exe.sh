#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DAEMON_BIN="${ROOT_DIR}/core/target/release/silicon-alloy-daemon"
CLI_BIN="${ROOT_DIR}/core/target/release/silicon-alloy"

usage() {
  cat <<'USAGE'
usage: run-exe.sh <bottle-name> <path-to-exe> [--channel CHANNEL] [--reuse]

  <bottle-name>   logical name for the wine bottle
  <path-to-exe>   windows installer or executable (.exe)

options:
  --channel CHANNEL   runtime channel (rossetta, native-arm64, etc.)
  --reuse             reuse existing bottle if it already exists

examples:
  scripts/run-exe.sh steam ~/Downloads/SteamSetup.exe
  scripts/run-exe.sh notepad++ ~/Downloads/npp.exe --channel native-arm64
USAGE
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

BOTTLE_NAME="$1"
shift
EXE_PATH="$1"
shift

CHANNEL="rossetta"
REUSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)
      CHANNEL="$2"
      shift 2
      ;;
    --reuse)
      REUSE=true
      shift
      ;;
    *)
      echo "unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -x "${DAEMON_BIN}" || ! -x "${CLI_BIN}" ]]; then
  echo "daemon or cli binaries not found. run scripts/bootstrap.sh first." >&2
  exit 1
fi

if [[ ! -f "${EXE_PATH}" ]]; then
  echo "exe not found: ${EXE_PATH}" >&2
  exit 1
fi

SOCKET_PATH="${HOME}/Library/Application Support/com.SiliconAlloy.SiliconAlloy/daemon.sock"
LOG_DIR="${HOME}/Library/Application Support/SiliconAlloy/logs"
mkdir -p "$(dirname "${SOCKET_PATH}")" "${LOG_DIR}"

if /usr/bin/lsof -t "${SOCKET_PATH}" >/dev/null 2>&1; then
  echo "existing daemon detected on socket. reusing."
else
  echo "starting daemon..."
  "${DAEMON_BIN}" &
  DAEMON_PID=$!
  trap 'kill ${DAEMON_PID} >/dev/null 2>&1 || true' EXIT
  sleep 2
fi

if ! ${CLI_BIN} list >/dev/null 2>&1; then
  echo "daemon unreachable on ${SOCKET_PATH}." >&2
  exit 1
fi

BOTTLE_ID=""
if ${REUSE}; then
  BOTTLE_ID="$(${CLI_BIN} list | jq -r --arg name "${BOTTLE_NAME}" '.bottles[] | select(.name==$name) | .id' | head -n1 || true)"
fi

if [[ -z "${BOTTLE_ID}" ]]; then
  echo "creating bottle ${BOTTLE_NAME} (channel: ${CHANNEL})"
  CREATE_OUTPUT="$(${CLI_BIN} create "${BOTTLE_NAME}" --wine-version 9.0 --channel "${CHANNEL}")"
  BOTTLE_ID="$(echo "${CREATE_OUTPUT}" | jq -r '.bottle.id')"
else
  echo "reusing bottle ${BOTTLE_NAME} (${BOTTLE_ID})"
fi

echo "running ${EXE_PATH} inside ${BOTTLE_NAME}"
${CLI_BIN} run "${BOTTLE_ID}" "${EXE_PATH}"

echo ""
echo "launcher complete. check ${LOG_DIR} for daemon logs and the app ui for status."

