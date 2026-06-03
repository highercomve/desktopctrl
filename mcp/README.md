# desktopctrl MCP server

A small [FastMCP](https://github.com/modelcontextprotocol/python-sdk) server that
exposes the `desktopctrl` CLI as MCP tools so an LLM client can control the
Hyprland/Wayland desktop: screenshots, mouse, keyboard, and window management.

It shells out to the `desktopctrl` binary, so it **inherits all of its
requirements** — most importantly a running `ydotoold` (see the top-level
[README](../README.md)). The server must run in your **real user session** (it
needs `WAYLAND_DISPLAY` and the ydotool socket); do not run it sandboxed.

## Tools

`screenshot`, `shot_window` (return PNG images) · `move`, `click`, `moveclick`,
`doubleclick`, `drag`, `cursorpos` · `type_text`, `key` · `windows`,
`active_window`, `locate`, `focus`, `launch`, `workspace`, `close_window` ·
`daemon_status`.

Coordinates are **logical pixels** — the same space a `screenshot` is captured
in. Typical loop: `screenshot` → find the target → `moveclick x y` → `screenshot`
to verify.

## Run it

[`run.sh`](run.sh) self-bootstraps — on first run it creates a venv, installs
dependencies, then execs the server (all setup output goes to stderr so stdout
stays a clean MCP stream). Subsequent runs start instantly.

```bash
./run.sh        # creates .venv, installs deps, runs the server over stdio
```

## Register with Claude Code

Point Claude Code at `run.sh` — no manual venv step needed. Pass
`DESKTOPCTRL_BIN` if the CLI isn't on PATH.

```bash
claude mcp add desktopctrl \
  --env DESKTOPCTRL_BIN="$HOME/.local/bin/desktopctrl" \
  -- /home/projects/personal/desktopctrl/mcp/run.sh
```

Or add it to your MCP config (`~/.claude.json` or project settings) manually:

```json
{
  "mcpServers": {
    "desktopctrl": {
      "command": "/home/projects/personal/desktopctrl/mcp/run.sh",
      "env": { "DESKTOPCTRL_BIN": "/home/sergiom/.local/bin/desktopctrl" }
    }
  }
}
```

Restart / reconnect the client to load the server, then verify with the
`daemon_status` tool. If it reports "not running", start the daemon with
`desktopctrl daemon` (see the top-level README).

## Notes

- Run `desktopctrl doctor` first — the MCP server only works if the CLI does.
- The server is intentionally a thin wrapper: all behavior (coordinate model,
  daemon lifecycle, calibration) lives in the CLI.
