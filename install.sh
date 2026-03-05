#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AIS_BIN="${SCRIPT_DIR}/bin/ais"
INSTALL_PATH="/usr/local/bin/ais"

trap 'echo "Error on line $LINENO" >&2' ERR

if [[ ! -f "$AIS_BIN" ]]; then
  echo "Error: bin/ais not found. Run this script from the project root." >&2
  exit 1
fi

chmod +x "$AIS_BIN"

if [[ -L "$INSTALL_PATH" || -f "$INSTALL_PATH" ]]; then
  echo "Removing existing ${INSTALL_PATH}..."
  rm -- "$INSTALL_PATH"
fi

ln -s -- "$AIS_BIN" "$INSTALL_PATH"
echo "Installed: ${INSTALL_PATH} -> ${AIS_BIN}"
echo ""
echo "Run 'ais config' to set up your API key."
