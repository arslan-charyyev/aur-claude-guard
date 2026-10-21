#!/usr/bin/env bash
# Remove aur-claude-guard, then the verdict cache that pacman does not own.
set -uo pipefail
run0 pacman -R aur-claude-guard || exit

cache=~/.cache/aur-claude-review
echo "==> Removing the verdict cache (if any)…"
rm -rf "$cache"

# AUR_REVIEW_CACHE can point anywhere, so a custom cache is left to the user.
if [[ -n ${AUR_REVIEW_CACHE:-} && ${AUR_REVIEW_CACHE%/} != "$cache" ]]; then
  echo "==> NOTE: AUR_REVIEW_CACHE is set. Delete that cache by hand: $AUR_REVIEW_CACHE"
fi
