# desktopctrl

Unified desktop control for **Hyprland / Wayland** — one small CLI that wraps
`grim` (screenshots), `ydotool` (mouse), `wtype` (keyboard) and `hyprctl`
(windows) behind a consistent interface, so scripts and LLM agents can *see and
drive* the real desktop.

```bash
desktopctrl screenshot                 # capture the screen -> PNG path
desktopctrl windows                    # list windows + geometry
desktopctrl focus chrome               # focus a window by substring
desktopctrl moveclick 1110 513         # click at logical pixel (1110,513)
desktopctrl type 'hello'               # type into the focused window
desktopctrl key ctrl+l                 # send a chord
```

It comes with an optional **MCP server** ([`mcp/`](mcp/)) and a **Claude Code
skill** so an agent can control the machine through the same tool.

## Why

Wayland deliberately has no global "type/click anywhere" API like X11's XTEST.
The pieces exist (`grim`, `ydotool`+`uinput`, `wtype`, `hyprctl`) but each has
its own flags, quirks, and coordinate space. `desktopctrl` unifies them and
handles the annoying bits: **ydotool's absolute-coordinate scaling**, the
**ydotoold daemon lifecycle**, and **rootless `/dev/uinput`** setup.

## Requirements

| Tool | Purpose | Arch package |
|---|---|---|
| `hyprctl` | window management (ships with Hyprland) | `hyprland` |
| `grim` | screenshots | `grim` |
| `ydotool` + `ydotoold` | mouse/keyboard injection via `/dev/uinput` | `ydotool` |
| `wtype` | typing / key chords | `wtype` |
| `jq`, `awk`, `bash` | glue | `jq` (awk/bash are usually present) |

Plus a running **`ydotoold`** daemon with an accessible socket. `desktopctrl
doctor` validates all of the above and tells you what's missing.

## Install

```bash
git clone git@github.com:highercomve/desktopctrl.git
cd desktopctrl
./install.sh
```

`install.sh` will:
1. check dependencies (and print the install command for any that are missing),
2. symlink `bin/desktopctrl` into `~/.local/bin`,
3. set up **rootless** `ydotoold`: install a udev rule for `/dev/uinput`, add you
   to the `input` group, load the `uinput` module,
4. install + enable a **`systemd --user`** service so `ydotoold` starts with your
   session,
5. install the **desktop-control agent skill** to `~/.agents/skills/desktop-control`
   and symlink it into every detected AI agent's skills dir (Claude Code, opencode,
   Cursor, …),
6. register the **MCP server** with Claude Code (`claude mcp add desktopctrl …` at
   user scope, so it's available in every project) — just like installing
   [playwright-mcp](https://github.com/microsoft/playwright-mcp). Reconnect Claude
   Code afterwards and call the `daemon_status` tool to verify.

Flags: `--cli-only` (just deps + symlink), `--no-systemd`, `--no-rootless`,
`--no-skill` (skip the agent skill), `--no-mcp` (skip MCP registration),
`--only-skill` (install *only* the skill), `--only-mcp` (register *only* the MCP
server), `--mcp-scope <local|user|project>` (MCP config scope, default `user`).

> After the first install you must **reboot** (or `loginctl terminate-user
> $USER` and log back in) so the `systemd --user` session picks up the new
> `input` group membership — a `newgrp input` shell alone won't fix the user
> manager's `/dev/uinput` access. Then run `desktopctrl doctor`.

### ydotoold without the rootless setup

`desktopctrl daemon` prefers the `systemd --user` service, then a **rootless**
daemon if `/dev/uinput` is writable. It will **never auto-escalate to root** —
a root `ydotoold` creates an unmanaged virtual input device that can perturb the
compositor (dropped bars/keybinds). If you really need a one-off root daemon,
opt in explicitly:

```bash
DESKTOPCTRL_SUDO=1 desktopctrl daemon
# equivalent: sudo ydotoold -p /tmp/.ydotool_socket -P 0666 &
```

If you're already in the `input` group but still get a `/dev/uinput` access
error, your session predates the group change — **reboot** and try again.

`desktopctrl` finds the socket automatically (`$YDOTOOL_SOCKET`, then
`$XDG_RUNTIME_DIR/.ydotool_socket`, then `/tmp/.ydotool_socket`).

## Coordinate model

All coordinates are **logical pixels** — the same space as `hyprctl cursorpos`
and a `scale=1` `grim` screenshot. ydotool's absolute axis is offset by a divisor
(default 2, auto-derived by `desktopctrl calibrate`), applied internally, so you
always pass logical coordinates. If clicks land off-target, run `calibrate`.

## Commands

```
screenshot [path]            full screen -> png (prints path)
shot-window [path]           active window -> png
move <x> <y>                 move cursor
click [left|right|middle]    click at current position
moveclick <x> <y> [btn]      move then click
doubleclick <x> <y>
drag <x1> <y1> <x2> <y2>
type <text...>               type text
key <combo>                  e.g. ctrl+l, Return, Escape, alt+Tab
cursorpos                    print cursor position
windows                      list mapped windows (focused marked *)
activewindow                 focused window info
locate <substr>              print centre "x y" of a matching window
focus <match>                focus window (class:/title:/address:/substr)
exec <cmd...>                launch an app
workspace <id> | close
daemon | daemon-stop | daemon-status   ydotoold lifecycle
calibrate                    derive the ydotool coordinate divisor
doctor                       validate the environment (exit non-zero if not ready)
version
```

## Typical agent workflow

```bash
desktopctrl doctor                       # is everything ready?
desktopctrl windows                      # what's open + where
desktopctrl focus chrome                 # focus a window
read x y < <(desktopctrl locate chrome)  # its centre
desktopctrl moveclick "$x" "$y"          # click it
desktopctrl key ctrl+l                    # address bar
desktopctrl type 'http://...' ; desktopctrl key Return
SHOT=$(desktopctrl screenshot)           # then view "$SHOT" to verify
```

## Agent skill

[`skill/`](skill/) is a portable "desktop-control" skill that teaches an AI agent
how to use `desktopctrl` correctly (sandbox/daemon requirements, the coordinate
model, finding targets, the command reference). `install.sh` places it at
`~/.agents/skills/desktop-control` and symlinks it into each detected agent.

## MCP server

[`mcp/`](mcp/) is a FastMCP server exposing the CLI as MCP tools (screenshots
return images). It self-bootstraps — point your MCP client at
[`mcp/run.sh`](mcp/run.sh), which creates a venv, installs deps, and runs the
server. See [mcp/README.md](mcp/README.md).

## Repository layout

```
bin/desktopctrl           the CLI
install.sh                installer / environment setup
systemd/ydotoold.service  systemd --user unit for the daemon
udev/99-uinput.rules      rootless /dev/uinput access
skill/SKILL.md            agent skill (installed to ~/.agents/skills)
mcp/                      FastMCP server (run.sh bootstraps venv + deps)
```

## Troubleshooting

- **`desktopctrl doctor`** is the first stop — it checks session, deps, uinput
  access, daemon, socket, and calibration.
- *"No such file or directory" for ydotool*: the daemon socket is missing or
  `ydotool` isn't installed — `desktopctrl daemon` / `doctor`.
- *Clicks land in the wrong place*: `desktopctrl calibrate`.
- *Mouse does nothing*: `ydotoold` isn't running, or `/dev/uinput` isn't
  accessible — re-run `./install.sh` and **reboot**, or force a root daemon with
  `DESKTOPCTRL_SUDO=1 desktopctrl daemon`.

## License

MIT — see [LICENSE](LICENSE).
