#!/usr/bin/env bash
# Remove aur-claude-guard and its per-user activation.
set -uo pipefail
sudo pacman -R aur-claude-guard
echo "==> If you don't plan to reinstall, remove the 'source /usr/share/aur-claude-guard/shell-hook.bash' line from ~/.bashrc."
