#!/usr/bin/env python3
"""desktopctrl MCP server.

Exposes the local `desktopctrl` CLI (Hyprland/Wayland desktop control) as MCP
tools: screenshots, mouse, keyboard, and window management. The server shells
out to the `desktopctrl` binary and must run in the user's real session (not a
sandbox) so it can reach Wayland + the ydotoold socket.

Coordinates are LOGICAL pixels — the same space a `screenshot` is captured in.
"""

import os
import shutil
import subprocess
import tempfile

from mcp.server.fastmcp import FastMCP, Image

DESKTOPCTRL = (
    os.environ.get("DESKTOPCTRL_BIN")
    or shutil.which("desktopctrl")
    or os.path.expanduser("~/.local/bin/desktopctrl")
)

mcp = FastMCP("desktopctrl")


class DesktopctrlError(RuntimeError):
    """Raised with an actionable message when the CLI fails."""


def run(*args: str, timeout: int = 30) -> str:
    """Invoke `desktopctrl <args>` and return stripped stdout, or raise."""
    if not (DESKTOPCTRL and os.path.exists(DESKTOPCTRL)):
        raise DesktopctrlError(
            "desktopctrl binary not found. Install it (~/.local/bin/desktopctrl) "
            "or set the DESKTOPCTRL_BIN environment variable."
        )
    try:
        proc = subprocess.run(
            [DESKTOPCTRL, *args],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        raise DesktopctrlError(f"desktopctrl {args[0]} timed out after {timeout}s")
    if proc.returncode != 0:
        msg = (proc.stderr or proc.stdout or "command failed").strip()
        # The most common failure mode: the input daemon isn't running.
        if "socket" in msg.lower() or "ydotool" in msg.lower():
            msg += " (is ydotoold running? check daemon_status)"
        raise DesktopctrlError(msg)
    return proc.stdout.strip()


def _shot(subcommand: str) -> Image:
    fd, path = tempfile.mkstemp(suffix=".png", prefix="desktopctrl-")
    os.close(fd)
    try:
        run(subcommand, path)
        with open(path, "rb") as fh:
            data = fh.read()
        return Image(data=data, format="png")
    finally:
        try:
            os.remove(path)
        except OSError:
            pass


# --- screen (read-only) ----------------------------------------------------

@mcp.tool()
def screenshot() -> Image:
    """Capture the full screen as a PNG. Use this to see the desktop before
    deciding where to click. Pixels in the image are logical coordinates (1:1
    with move/click at scale 1)."""
    return _shot("screenshot")


@mcp.tool()
def shot_window() -> Image:
    """Capture only the currently focused window as a PNG."""
    return _shot("shot-window")


# --- mouse -----------------------------------------------------------------

@mcp.tool()
def move(x: int, y: int) -> str:
    """Move the mouse cursor to logical pixel (x, y)."""
    run("move", str(x), str(y))
    return f"moved to {x},{y}"


@mcp.tool()
def click(button: str = "left") -> str:
    """Click at the current cursor position. button: left | right | middle."""
    run("click", button)
    return f"{button} click"


@mcp.tool()
def moveclick(x: int, y: int, button: str = "left") -> str:
    """Move to logical (x, y) then click. button: left | right | middle.
    This is the usual way to click a UI element located in a screenshot."""
    run("moveclick", str(x), str(y), button)
    return f"{button} click at {x},{y}"


@mcp.tool()
def doubleclick(x: int, y: int) -> str:
    """Double left-click at logical (x, y)."""
    run("doubleclick", str(x), str(y))
    return f"double-click at {x},{y}"


@mcp.tool()
def drag(x1: int, y1: int, x2: int, y2: int) -> str:
    """Press the left button at (x1, y1), drag to (x2, y2), and release."""
    run("drag", str(x1), str(y1), str(x2), str(y2))
    return f"dragged {x1},{y1} -> {x2},{y2}"


@mcp.tool()
def cursorpos() -> str:
    """Return the current mouse cursor position (logical pixels)."""
    return run("cursorpos")


# --- keyboard --------------------------------------------------------------

@mcp.tool()
def type_text(text: str) -> str:
    """Type literal text into the focused window."""
    run("type", text)
    return f"typed {len(text)} chars"


@mcp.tool()
def key(combo: str) -> str:
    """Send a key or chord to the focused window. Examples: 'Return', 'Escape',
    'Tab', 'ctrl+l', 'alt+Tab', 'ctrl+shift+t'. Modifiers are '+'-joined."""
    run("key", combo)
    return f"key {combo}"


# --- windows ---------------------------------------------------------------

@mcp.tool()
def windows() -> str:
    """List mapped windows (focused marked '*'): workspace, class, geometry,
    address, and title. Use to find a window's position for clicking."""
    return run("windows") or "(no windows)"


@mcp.tool()
def active_window() -> str:
    """Info about the focused window: class, title, geometry, address."""
    return run("activewindow")


@mcp.tool()
def locate(substr: str) -> str:
    """Return the logical centre 'x y' of the first window whose class or title
    contains `substr` (case-insensitive). Handy as a click target."""
    out = run("locate", substr)
    return out or f"(no window matching '{substr}')"


@mcp.tool()
def focus(match: str) -> str:
    """Focus a window by 'class:NAME', 'title:NAME', 'address:0x..', or a bare
    substring of its class/title. Returns the now-focused window."""
    return run("focus", match)


@mcp.tool()
def launch(cmd: str) -> str:
    """Launch an application via the compositor (hyprctl dispatch exec)."""
    run("exec", cmd)
    return f"launched: {cmd}"


@mcp.tool()
def workspace(workspace_id: str) -> str:
    """Switch to a Hyprland workspace by id."""
    run("workspace", workspace_id)
    return f"workspace {workspace_id}"


@mcp.tool()
def close_window() -> str:
    """Close the currently focused window (killactive). Destructive."""
    run("close")
    return "closed focused window"


# --- health ----------------------------------------------------------------

@mcp.tool()
def daemon_status() -> str:
    """Report whether the ydotoold input daemon is running. Mouse/keyboard tools
    need it; if it is not running the user must start it (`desktopctrl daemon`)."""
    return run("daemon-status")


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
