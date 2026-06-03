---
name: desktop-control
description: Control the local Hyprland/Wayland desktop via the `desktopctrl` CLI — take screenshots, move/click/drag the mouse, type text and key combos, and manage windows (list/focus/launch/locate/workspace). Use when the user asks to control the computer, click or type in a real GUI app, drive the real browser (e.g. real Chrome rather than Playwright), open or interact with a file manager, screenshot the desktop, or automate any on-screen desktop task. Requires Hyprland + a running ydotoold daemon (set up by the desktopctrl project's install.sh).
---

# Desktop Control

Drive the real desktop with `desktopctrl` (wraps `grim`, `ydotool`, `wtype`, `hyprctl`).
The CLI is installed on PATH by the desktopctrl project's `install.sh` (canonical at
`~/.local/bin/desktopctrl`). Always start with `desktopctrl doctor` to confirm the
environment is ready.

## Two hard requirements (read first)

1. **Run every `desktopctrl` call with the command sandbox DISABLED** (e.g. Bash
   `dangerouslyDisableSandbox: true`). `ydotool` is often outside the agent shell's
   filesystem snapshot, so sandboxed calls fail with "No such file or directory".

2. **`ydotoold` must be running.** Check `desktopctrl daemon-status`. If it says
   "not running", ask the user to run `desktopctrl daemon` themselves (or
   `./install.sh` once for a persistent rootless `systemd --user` daemon, then
   **reboot**). `desktopctrl daemon` never auto-escalates to root — if `/dev/uinput`
   is inaccessible it tells the user how to fix it (reboot after install, or opt
   into a root daemon with `DESKTOPCTRL_SUDO=1 desktopctrl daemon`). Don't try to
   sudo it yourself. Mouse/keyboard tools don't work without the daemon.

## Coordinate model

All coordinates are **LOGICAL pixels** — the same space as `hyprctl cursorpos` and a
scale-1 `grim` screenshot. Pass logical coords to `move`/`moveclick`/etc.; the ydotool
axis divisor is auto-calibrated and applied internally. Do **not** pre-divide. If
clicks land off-target, run `desktopctrl calibrate`.

## Finding click targets

- Prefer **`windows`** and **`locate <substr>`** for exact geometry — `locate` prints
  the logical centre `x y` of the first window whose class/title matches.
- A `screenshot` prints a PNG path; read it to see the screen. **Caveat:** the image
  may be downscaled when viewed, so eyeballed pixels are approximate. For precision,
  derive targets from window geometry (`windows`/`activewindow`/`locate`) or compute an
  element's position as a fraction of the window box, then confirm with a fresh shot.
- Prefer **keyboard** over fragile clicks where possible (browser: `key ctrl+l` → focus
  address bar, `type <url>`, `key Return`; dialogs: `Tab`/`Return`/`Escape`).

## Typical workflow

```bash
# (all with the sandbox disabled)
desktopctrl doctor                        # is everything ready?
desktopctrl windows                       # see what's open + geometry
desktopctrl focus chrome                  # focus a window by substring
read x y < <(desktopctrl locate chrome)   # centre of that window
desktopctrl moveclick "$x" "$y"           # click it
desktopctrl key ctrl+l                     # focus address bar
desktopctrl type 'http://...' ; desktopctrl key Return
SHOT=$(desktopctrl screenshot)            # capture, then read "$SHOT" to verify
```

## Command reference

| Command | Purpose |
|---|---|
| `screenshot [path]` | Full screen → PNG (prints path) |
| `shot-window [path]` | Active window only → PNG |
| `move <x> <y>` | Move cursor (logical px) |
| `click [left\|right\|middle]` | Click at current position |
| `moveclick <x> <y> [btn]` | Move then click |
| `doubleclick <x> <y>` | Double left-click |
| `drag <x1> <y1> <x2> <y2>` | Press-drag-release (left) |
| `type <text...>` | Type literal text |
| `key <combo>` | Key / chord: `ctrl+l`, `Return`, `Escape`, `alt+Tab`, `ctrl+shift+t` |
| `cursorpos` | Print current cursor position |
| `windows` | List mapped windows (focused `*`): ws, class, geometry, address, title |
| `activewindow` | Focused window info |
| `locate <substr>` | Print centre `x y` of first window matching class/title |
| `focus <match>` | Focus window: `class:..`, `title:..`, `address:0x..`, or a bare substring |
| `exec <cmd...>` | Launch an app |
| `workspace <id>` / `close` | Switch workspace / close focused window |
| `daemon` / `daemon-stop` / `daemon-status` | ydotoold lifecycle |
| `calibrate` | Re-derive the ydotool coordinate divisor |
| `doctor` | Validate the environment (exit non-zero if not ready) |

## Notes & gotchas

- New `exec` windows open on the current workspace and usually grab focus; you can't
  click across workspaces — `workspace <id>` first.
- After typing into a terminal, nothing runs until `key Return`.
- `type` sends literal text (single-quote for shell safety); `key` is for named keys and
  modifier chords (`mod+mod+key`, parsed left-to-right).
- Verifying results by reading files (e.g. a download's real filename from an app's
  history DB) is often more reliable than visual inspection.
