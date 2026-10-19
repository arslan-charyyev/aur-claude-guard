#!/usr/bin/env bash
# Remove aur-claude-guard.
set -uo pipefail
run0 pacman -R aur-claude-guard
