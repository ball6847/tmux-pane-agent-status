#!/usr/bin/env bash
# tab-name-hook.sh — after-rename-window hook body.
#
# `rename-window` (prefix + , or the rename-window command) turns
# automatic-rename off for the window, freezing the tab and dropping the
# plugin's status icon. This hook stashes the manually chosen name in the
# window's @tab_name user option and turns dynamic naming back on, so
# pane-label.sh can render "● asd": the live icon plus the chosen name.
#
# Automatic renames reach this hook too; they are ignored because they only
# happen with automatic-rename still on. An empty rename clears @tab_name.
#
# Usage:
#   tab-name-hook.sh <window-id>

set -euo pipefail

window_id="${1:?usage: tab-name-hook.sh <window-id>}"

# Only manual renames leave automatic-rename off; bail on automatic ones.
auto="$(tmux display -p -t "$window_id" '#{automatic-rename}' 2>/dev/null || true)"
[ "$auto" = "0" ] || exit 0

# Read the name before re-enabling dynamic naming: the next automatic rename
# would overwrite it.
name="$(tmux display -p -t "$window_id" '#{window_name}' 2>/dev/null || true)"

tmux set-option -w -t "$window_id" @tab_name "$name"
tmux set-option -w -t "$window_id" automatic-rename on
