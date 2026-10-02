#!/bin/bash
# agent-state.sh — Agent state detection for the tmux status bar.
#
# Scans all panes for running coding agents and reports their state:
#   ⟳ name  – agent is actively working
#   ⌨ name  – agent is blocked on a prompt, waiting for user input
#   ⌄ name  – agent is idle: screen unchanged for IDLE_AFTER_SECONDS
#
# Called from status-right via #() expansion every status-interval.

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agents.sh
. "$CURRENT_DIR/agents.sh"
# shellcheck source=state.sh
. "$CURRENT_DIR/state.sh"

output=""
agent_panes=""

while read -r pane_id cmd; do
	[ -z "$cmd" ] && continue

	name="$(agent_name "$pane_id" "$cmd")"
	[ -n "$name" ] || continue

	agent_panes="$agent_panes ${pane_id#\%} "

	# One capture feeds both the prompt heuristic and the change detector.
	screen="$(tmux capture-pane -t "$pane_id" -p 2>/dev/null || true)"

	case "$(agent_state "$pane_id" "$screen")" in
		waiting) icon="$WAITING_ICON" ;;
		idle) icon="$IDLE_ICON" ;;
		*) icon="$WORKING_ICON" ;;
	esac

	output="$output ${icon}${name}"

done < <(tmux list-panes -a -F '#{pane_id} #{pane_current_command}' 2>/dev/null || true)

# Forget panes that no longer run an agent. The glob is not a subshell, and rm
# only forks when there is something to remove.
dir="$(agent_state_dir)"
for state_file in "$dir"/*; do
	[ -e "$state_file" ] || continue
	case "$agent_panes" in
		*" ${state_file##*/} "*) continue ;;
	esac
	rm -f "$state_file"
done

# Strip the leading space without spawning sed.
printf '%s\n' "${output# }"