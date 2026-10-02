#!/usr/bin/env bash
# label-regen.sh — force-regenerate the AI tab label for a pane.
#
# Bound to <prefix> G (and runnable by hand):
#   tmux run-shell '<plugin>/scripts/label-regen.sh #{pane_id}'
#
# Clears the window's @ai_label, drops the .labelfired exactly-once marker so
# a future growth tick may fire again, re-baselines .labelmeta at the current
# screen size, and forks label-gen.sh immediately so the new name arrives in
# ~10-30s without waiting for more output. Silent unless the pane runs no
# known agent. Never fails the tmux caller.
#
# Usage:
#   label-regen.sh <pane-id>

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agents.sh
. "$CURRENT_DIR/agents.sh"
# shellcheck source=state.sh
. "$CURRENT_DIR/state.sh"

pane_id="${1:?usage: label-regen.sh <pane-id>}"
window_id="$(tmux display -t "$pane_id" -p '#{window_id}' 2>/dev/null || true)"
# AI labels disabled for now — delete this block to re-enable.
[ -n "$window_id" ] && tmux display-message -t "$window_id" "AI tab labels disabled" 2>/dev/null || true
exit 0
cmd="$(tmux display -t "$pane_id" -p '#{pane_current_command}' 2>/dev/null || true)"

if [ -z "$(agent_name "$pane_id" "$cmd")" ]; then
	tmux display-message -t "$window_id" "No coding agent in this pane" 2>/dev/null || true
	exit 0
fi

dir="$(agent_state_dir)"
key="${pane_id#\%}"
screen="$(tmux capture-pane -t "$pane_id" -p 2>/dev/null || true)"
printf '%s\n' "${#screen}" >"$dir/$key.labelmeta" 2>/dev/null || true
rm -f "$dir/$key.labelfired" 2>/dev/null || true
tmux set-option -w -t "$window_id" @ai_label '' 2>/dev/null || true
tmux set-option -w -t "$window_id" @ai_label_pane '' 2>/dev/null || true

if [ -x "$CURRENT_DIR/label-gen.sh" ]; then
	nohup "$CURRENT_DIR/label-gen.sh" "$pane_id" </dev/null >/dev/null 2>&1 & disown 2>/dev/null || true
	tmux display-message -t "$window_id" "Regenerating tab label…" 2>/dev/null || true
fi
exit 0
