#!/bin/bash
# agent-state.sh — Lightweight agent state detection for tmux status bar.
#
# Scans all panes for running coding agents and reports their state:
#   ⟳ name  – agent is actively working
#   ⌨ name  – agent is blocked on a prompt, waiting for user input
#   ⌄ name  – agent is idle: screen unchanged for IDLE_TICKS samples
#
# Called from status-right via #() expansion every status-interval.

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agents.sh
. "$CURRENT_DIR/agents.sh"

# A line longer than this is prose, not an interactive prompt.
MAX_PROMPT_LENGTH=120

# Consecutive identical screen captures before an agent counts as idle. At the
# default status-interval of 15s this would take 45s, so drop status-interval
# to 1 if you want idle to be noticed promptly. Raise it for agents that sit
# still for a while while still working.
IDLE_TICKS=3

WORKING_ICON="⟳"
WAITING_ICON="⌨"
IDLE_ICON="⌄"

# Strip trailing whitespace, then a trailing prompt marker such as the "> ",
# "❯ " or "$ " that shells append. Two passes handles "$ ❯ ".
agent_trim_prompt() {
	local line="$1"
	local i
	for i in 1 2; do
		line="${line%"${line##*[![:space:]]}"}"
		case "$line" in
			'>' | '$' | '#' | '%' | ':' | '❯' | '›' | '»' | '│')
				line="${line%?}"
				;;
			*) break ;;
		esac
	done
	printf '%s' "$line"
}

# Decide whether a captured screen is blocked on the user.
#
# Only the final non-empty line is inspected. Scanning the whole pane meant a
# prompt that had already scrolled up still counted, so panes that were
# actively working were reported as waiting.
agent_waiting_prompt() {
	local screen="$1"
	local last_line trimmed

	[ -n "$screen" ] || return 1

	# `|| true` guards pipefail: an entirely blank capture would otherwise
	# abort the script mid-loop.
	last_line="$(printf '%s\n' "$screen" | grep -v '^[[:space:]]*$' | tail -n 1 || true)"
	[ -n "$last_line" ] || return 1

	# Explicit confirmation prompts.
	case "$last_line" in
		*'[y/N]'* | *'[Y/n]'* | *'[Y/N]'* | *'[y/n]'*) return 0 ;;
		*'Continue?'* | *'Proceed?'* | *' (Y/n):'* | *' (y/N):'* | *' (y/n):'* | *' (Y/N):'*) return 0 ;;
		*'Press Enter'* | *'Press any key'*) return 0 ;;
	esac

	# Generic question. The line has to actually END with '?'. Merely
	# containing one is far too common in agent output ("Ready? Let me know
	# what to change") and made almost every busy pane look blocked.
	trimmed="$(agent_trim_prompt "$last_line")"
	case "$trimmed" in
		*'?')
			[ "${#trimmed}" -le "$MAX_PROMPT_LENGTH" ] && return 0
			;;
	esac

	return 1
}

# State has to survive between invocations: tmux re-runs this script from
# scratch on every status refresh, so the previous screen hash is kept on disk.
# Keyed by socket path because pane ids (%0, %1, ...) are only unique within a
# single tmux server.
socket_path="$(tmux display -p '#{socket_path}' 2>/dev/null || true)"
[ -n "$socket_path" ] || socket_path="default"
state_dir="${TMPDIR:-/tmp}/tmux-agent-status-${socket_path//[^A-Za-z0-9._-]/_}"
[ -d "$state_dir" ] || mkdir -p "$state_dir"

output=""
agent_panes=""

while read -r pane_id cmd; do
	[ -z "$cmd" ] && continue

	name="$(agent_name "$pane_id" "$cmd")"
	[ -n "$name" ] || continue

	agent_panes="$agent_panes ${pane_id#\%} "

	# One capture feeds both the prompt heuristic and the change detector.
	screen="$(tmux capture-pane -t "$pane_id" -p 2>/dev/null || true)"

	state_file="$state_dir/${pane_id#\%}"
	prev_hash=""
	prev_streak=0
	if [ -f "$state_file" ]; then
		read -r prev_hash prev_streak <"$state_file" || true
	fi
	case "$prev_streak" in
		'' | *[!0-9]*) prev_streak=0 ;;
	esac

	hash="$(printf '%s' "$screen" | cksum)"
	hash="${hash%% *}"

	if [ "$hash" = "$prev_hash" ]; then
		streak=$((prev_streak + 1))
	else
		streak=0
	fi
	printf '%s %s\n' "$hash" "$streak" >"$state_file"

	if agent_waiting_prompt "$screen"; then
		icon="$WAITING_ICON"
	elif [ "$streak" -ge "$IDLE_TICKS" ]; then
		icon="$IDLE_ICON"
	else
		icon="$WORKING_ICON"
	fi

	output="$output ${icon}${name}"

done < <(tmux list-panes -a -F '#{pane_id} #{pane_current_command}' 2>/dev/null || true)

# Forget panes that no longer run an agent. The glob is not a subshell, and rm
# only forks when there is something to remove.
for state_file in "$state_dir"/*; do
	[ -e "$state_file" ] || continue
	case "$agent_panes" in
		*" ${state_file##*/} "*) continue ;;
	esac
	rm -f "$state_file"
done

# Strip the leading space without spawning sed.
printf '%s\n' "${output# }"