#!/usr/bin/env bash
#
# Bootstrap + run the desktopctrl MCP server.
# Creates a local venv on first run, installs dependencies, then execs the
# server over stdio. Idempotent: subsequent runs skip setup and start instantly.
#
# Use this as the MCP `command` in your client config — it self-installs.
#
# All setup output goes to stderr so stdout stays a clean MCP/JSON-RPC stream.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="${DESKTOPCTRL_MCP_VENV:-$HERE/.venv}"
PYTHON="${PYTHON:-python3}"

{
	if [ ! -x "$VENV/bin/python" ]; then
		echo "desktopctrl-mcp: creating venv at $VENV" >&2
		"$PYTHON" -m venv "$VENV"
	fi
	# (Re)install only when the mcp package isn't importable yet.
	if ! "$VENV/bin/python" -c "import mcp" 2>/dev/null; then
		echo "desktopctrl-mcp: installing dependencies" >&2
		"$VENV/bin/python" -m pip install -q --upgrade pip
		"$VENV/bin/python" -m pip install -q -r "$HERE/requirements.txt"
	fi
} >&2

exec "$VENV/bin/python" "$HERE/desktopctrl_mcp.py" "$@"
