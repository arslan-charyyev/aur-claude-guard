#!/usr/bin/env bash
# Build + install aur-claude-guard, then migrate off the pieces of earlier
# versions: user-space copies, the update-check timer, and the yay shell hook.
# Idempotent.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

# The .pkg.tar.zst is a throwaway: write it to a temp dir (cleaned on exit)
# instead of littering the repo.
build_tmp="$(mktemp -d)"
trap 'rm -rf "$build_tmp"' EXIT

echo "==> Building the package…"
PKGDEST="$build_tmp" makepkg -f

echo "==> Installing the package (run0 asks for authentication)…"
run0 pacman -U --needed "$build_tmp"/*.pkg.tar.*

echo "==> Removing superseded user-space copies (if any)…"
rm -f ~/.local/bin/aur-claude-review ~/.local/bin/aur-update-check

echo "==> Removing the retired update-check timer (if any)…"
systemctl --user disable --now aur-update-check.timer 2>/dev/null || true
rm -f ~/.config/systemd/user/aur-update-check.service ~/.config/systemd/user/aur-update-check.timer
rm -rf ~/.config/aur-claude-guard
systemctl --user daemon-reload

if [ -f ~/.bashrc ] && grep -q 'aur-claude-guard/shell-hook.bash' ~/.bashrc; then
  echo "==> NOTE: the yay shell hook is retired. Remove its line from ~/.bashrc:"
  grep -n 'aur-claude-guard/shell-hook.bash' ~/.bashrc | sed 's/^/      /'
fi

echo "==> Done. makepkg now reviews every AUR build, from yay and Pamac alike."
