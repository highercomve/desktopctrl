#!/usr/bin/env bash
#
# desktopctrl installer.
#  - validates dependencies
#  - symlinks bin/desktopctrl into ~/.local/bin
#  - (optional) sets up rootless ydotoold: udev rule + input group + uinput module
#  - (optional) installs & enables the systemd --user service for ydotoold
#
# Usage:
#   ./install.sh                 # full install (CLI + rootless + systemd)
#   ./install.sh --cli-only      # just the dependency check + symlink
#   ./install.sh --no-systemd    # rootless setup but don't enable the user service
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local/bin}"
DO_ROOTLESS=1; DO_SYSTEMD=1
for a in "$@"; do case "$a" in
	--cli-only)   DO_ROOTLESS=0; DO_SYSTEMD=0 ;;
	--no-systemd) DO_SYSTEMD=0 ;;
	--no-rootless) DO_ROOTLESS=0 ;;
	-h|--help) sed -n '2,14p' "$0"; exit 0 ;;
	*) echo "unknown option: $a" >&2; exit 1 ;;
esac; done

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
err()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; }

pkg_hint() {
	if   command -v pacman >/dev/null;  then echo "sudo pacman -S --needed $*";
	elif command -v apt    >/dev/null;  then echo "sudo apt install $*";
	elif command -v dnf    >/dev/null;  then echo "sudo dnf install $*";
	else echo "install: $*"; fi
}

# 1. Dependencies -----------------------------------------------------------
info "Checking dependencies"
REQ=(hyprctl grim wtype ydotool ydotoold jq awk bash)
missing=()
for b in "${REQ[@]}"; do
	if command -v "$b" >/dev/null 2>&1; then ok "$b"; else err "$b missing"; missing+=("$b"); fi
done
if [ "${#missing[@]}" -gt 0 ]; then
	echo
	err "Missing: ${missing[*]}"
	echo "    Try:  $(pkg_hint "${missing[*]}")"
	echo "    (grim wtype ydotool jq are the usual package names; hyprctl ships with hyprland)"
	exit 1
fi

# 2. Symlink the CLI --------------------------------------------------------
info "Installing CLI -> $PREFIX/desktopctrl"
mkdir -p "$PREFIX"
chmod +x "$HERE/bin/desktopctrl"
ln -sf "$HERE/bin/desktopctrl" "$PREFIX/desktopctrl"
ok "linked $PREFIX/desktopctrl -> $HERE/bin/desktopctrl"
case ":$PATH:" in *":$PREFIX:"*) ;; *) err "$PREFIX is not in PATH — add it to your shell rc" ;; esac

# 3. Rootless uinput --------------------------------------------------------
if [ "$DO_ROOTLESS" = 1 ]; then
	info "Setting up rootless uinput access (needs sudo)"
	sudo install -m 0644 "$HERE/udev/99-uinput.rules" /etc/udev/rules.d/99-uinput.rules
	ok "installed /etc/udev/rules.d/99-uinput.rules"
	echo uinput | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
	sudo modprobe uinput || true
	ok "uinput module loaded + set to load at boot"
	sudo udevadm control --reload-rules && sudo udevadm trigger /dev/uinput || true
	ok "udev rules reloaded"
	if id -nG | tr ' ' '\n' | grep -qx input; then
		ok "user already in 'input' group"
	else
		sudo usermod -aG input "$USER"
		ok "added $USER to 'input' group  (RE-LOGIN required for this to take effect)"
		NEED_RELOGIN=1
	fi
fi

# 4. systemd --user service -------------------------------------------------
if [ "$DO_SYSTEMD" = 1 ]; then
	info "Installing systemd --user service for ydotoold"
	mkdir -p "$HOME/.config/systemd/user"
	install -m 0644 "$HERE/systemd/ydotoold.service" "$HOME/.config/systemd/user/ydotoold.service"
	systemctl --user daemon-reload
	if [ "${NEED_RELOGIN:-0}" = 1 ]; then
		systemctl --user enable ydotoold.service
		ok "enabled ydotoold.service (will start after you re-login for the group change)"
	else
		systemctl --user enable --now ydotoold.service && ok "enabled + started ydotoold.service" \
			|| err "could not start service — check: systemctl --user status ydotoold"
	fi
fi

# 5. Skill (for AI agents) --------------------------------------------------
info "Installing the desktop-control skill"
AGENTS_SKILLS="$HOME/.agents/skills"
mkdir -p "$AGENTS_SKILLS"
ln -sfn "$HERE/skill" "$AGENTS_SKILLS/desktop-control"
ok "master: $AGENTS_SKILLS/desktop-control -> $HERE/skill"

# Symlink the master skill into every present agent's skills dir. Only agents
# whose config dir already exists are touched. Override the list with
# DESKTOPCTRL_SKILL_DIRS="dir1 dir2 ...".
default_skill_dirs=(
	"$HOME/.claude/skills"            # Claude Code
	"$HOME/.config/opencode/skills"  # opencode
	"$HOME/.cursor/skills"           # Cursor
	"$HOME/.codex/skills"            # Codex
	"$HOME/.gemini/skills"           # Gemini CLI
)
read -ra skill_dirs <<< "${DESKTOPCTRL_SKILL_DIRS:-${default_skill_dirs[*]}}"
for d in "${skill_dirs[@]}"; do
	[ "$d" = "$AGENTS_SKILLS" ] && continue
	[ -d "$(dirname "$d")" ] || continue          # agent not installed -> skip
	mkdir -p "$d"
	target="$d/desktop-control"
	[ -e "$target" ] && [ ! -L "$target" ] && rm -rf "$target"   # replace a real dir
	ln -sfn "$AGENTS_SKILLS/desktop-control" "$target"
	ok "linked $target"
done

echo
info "Done. Validate with:  desktopctrl doctor"
[ "${NEED_RELOGIN:-0}" = 1 ] && echo "  NOTE: log out/in (or run 'newgrp input') so the input-group membership applies, then 'desktopctrl daemon'."
