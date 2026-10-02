#!/usr/bin/env bash
# tmux-pane-agent-status.tmux — Live status labels for tmux window tabs and
# status bar.
#
# TPM (tmux plugin manager) executes `*.tmux` files rather than passing them
# to `tmux source-file`, so this file is a shell script that drives tmux via
# `tmux` commands. That also keeps it independent of where the plugin was
# installed: paths are resolved relative to this script instead of being
# hardcoded to ~/.tmux/plugins.
#
# Install via TPM:
#   set -g @plugin 'duyet/tmux-pane-agent-status'
#
# Or run it directly / from a bootstrap script:
#   ~/.tmux/plugins/tmux-pane-agent-status/tmux-pane-agent-status.tmux

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL_SCRIPT="$CURRENT_DIR/scripts/pane-label.sh"
STATE_SCRIPT="$CURRENT_DIR/scripts/agent-state.sh"
TAB_NAME_HOOK="$CURRENT_DIR/scripts/tab-name-hook.sh"

if ! tmux display-message -p '#{pid}' >/dev/null 2>&1; then
	echo "tmux-pane-agent-status: must be run from inside tmux" >&2
	exit 1
fi

for script in "$LABEL_SCRIPT" "$STATE_SCRIPT" "$TAB_NAME_HOOK"; do
	if [ ! -x "$script" ]; then
		echo "tmux-pane-agent-status: missing or non-executable $script" >&2
		exit 1
	fi
done

# ── Window tab labels ────────────────────────────────────────────────────────
# Shows the active pane's foreground command as an icon + name. tmux does this
# natively via `#{pane_current_command}`; we swap in a script that classifies it.
# Quotes around the path keep spaces in the install directory working.
tmux set-option -g automatic-rename-format \
	"#{?pane_in_mode,[tmux],#(\"$LABEL_SCRIPT\" #{pane_id})}#{?pane_dead,[dead],}"

# <prefix> + R — back to fully dynamic naming: drops the custom name set with
# rename-window / prefix + , and re-enables automatic-rename on the window.
tmux bind-key R set-window-option automatic-rename on \
	\; set-option -w @tab_name '' \
	\; display-message "Dynamic naming ON"

# ── Custom tab names ─────────────────────────────────────────────────────────
# rename-window (prefix + ,) turns automatic-rename off for the window, which
# freezes the tab and drops the status icon. The hook stashes the chosen name
# in the window's @tab_name user option and turns dynamic naming back on, so
# the tab reads "⟳ asd": live icon plus the chosen name. pane-label.sh prefers
# @tab_name over the detected name. Renaming to empty clears it.
tmux set-hook -g after-rename-window \
	"run-shell '$TAB_NAME_HOOK #{window_id}'"

# ── Status bar ───────────────────────────────────────────────────────────────
# One icon per pane running a coding agent, across every pane on the server.
# NOTE: this overrides status-right. To keep your own layout, call
# scripts/agent-state.sh from your status-right instead of using this line.
tmux set-option -g status-right "#(\"$STATE_SCRIPT\") | %H:%M %d-%b-%y"