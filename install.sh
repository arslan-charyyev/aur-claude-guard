#!/usr/bin/env bash
# Build + install aur-claude-guard, then migrate off any earlier user-space
# (~/.local, ~/.config) copies and the retired update-check timer. Idempotent.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

echo "==> Building and installing the package (pacman will ask for your sudo password)…"
# makepkg's -i installs the built package immediately, so the .pkg.tar.zst is a
# throwaway. Write it to a temp dir (cleaned on exit) instead of littering the repo.
build_tmp="$(mktemp -d)"
trap 'rm -rf "$build_tmp"' EXIT
PKGDEST="$build_tmp" makepkg -sif

echo "==> Removing superseded user-space copies (if any)…"
rm -f ~/.local/bin/aur-claude-review ~/.local/bin/aur-update-check

echo "==> Removing the retired update-check timer (if any)…"
systemctl --user disable --now aur-update-check.timer 2>/dev/null || true
rm -f ~/.config/systemd/user/aur-update-check.service ~/.config/systemd/user/aur-update-check.timer
rm -rf ~/.config/aur-claude-guard
systemctl --user daemon-reload

if ! grep -q 'aur-claude-guard/shell-hook.bash' ~/.bashrc; then
  echo "==> NOTE: add this to ~/.bashrc to load the yay guard:"
  echo "      source /usr/share/aur-claude-guard/shell-hook.bash"
fi

echo "==> Done. Run 'source ~/.bashrc' or open a new terminal to load the guard."
