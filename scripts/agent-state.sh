#!/bin/bash
# agent-state.sh — Lightweight agent state detection for tmux status bar.
#
# Scans all panes for running coding agents and reports their state:
#   ⟳ name  – agent is actively running / working
#   ⌨ name  – agent is waiting for user input (heuristic)
#
# Called from status-right via #() expansion every status-interval.
# Fast: ~2ms per pane (list-panes + capture-pane of 3 lines).

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agents.sh
. "$CURRENT_DIR/agents.sh"

# A line longer than this is prose, not an interactive prompt.
MAX_PROMPT_LENGTH=120

# Strip trailing whitespace, then a trailing prompt marker such as the "> ",
# "❯ " or "$ " that shells append. Two passes handles "$ ❯ ".
agent_trim_prompt() {
	local line="$1"
	local i
	for i in 1 2; do
		line="${line%"${line##*[![:space:]]}"}"
		case "$line" in
			'>' | '$' | '#' | '%' | ':' | '❯' | '›' | '»' | '│' | '»')
				line="${line%?}"
				;;
			*) break ;;
		esac
	done
	printf '%s' "$line"
}

# Decide whether a pane looks like it is blocked on the user.
#
# Only the final non-empty line of the pane is inspected. Scanning the whole
# 3-line window meant a prompt that had already scrolled up still counted, so
# panes that were actively working were reported as waiting.
agent_is_waiting() {
	local _pane_id="$1"
	local last last_line trimmed

	last="$(tmux capture-pane -t "$_pane_id" -p -S -3 2>/dev/null || true)"
	[ -n "$last" ] || return 1

	# `|| true` guards pipefail: every captured line being blank would
	# otherwise abort the whole script mid-loop.
	last_line="$(printf '%s\n' "$last" | grep -v '^[[:space:]]*$' | tail -n 1 || true)"
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

output=""

while read -r pane_id cmd; do
	[ -z "$cmd" ] && continue

	name="$(agent_name "$pane_id" "$cmd")"
	[ -n "$name" ] || continue

	if agent_is_waiting "$pane_id"; then
		icon="⌨"
	else
		icon="⟳"
	fi

	output="$output ${icon}${name}"

done < <(tmux list-panes -a -F '#{pane_id} #{pane_current_command}' 2>/dev/null || true)

# Strip the leading space without spawning sed.
printf '%s\n' "${output# }"