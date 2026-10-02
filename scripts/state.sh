#!/usr/bin/env bash
# state.sh — working / waiting / idle detection, shared by pane-label.sh and
# agent-state.sh so the window tab and the status bar can never disagree.
#
# Exposes:
#   WORKING_ICON WAITING_ICON IDLE_ICON
#   IDLE_AFTER_SECONDS MAX_PROMPT_LENGTH
#   agent_waiting_prompt <screen>
#   agent_state <pane-id> [screen]   -> working|waiting|idle, refreshes state
#   agent_state_cached <pane-id>     -> last recorded state, or empty
#
# Each pane's state is one line of "<screen hash> <last change epoch> <state>".

WORKING_ICON="⟳"
WAITING_ICON="⌨"
IDLE_ICON="⌄"

# Seconds an agent's screen must stay unchanged before it counts as idle.
#
# Wall-clock seconds, not a tick counter. tmux evaluates
# automatic-rename-format more often than status-interval — pane-label.sh runs
# roughly twice per second where agent-state.sh runs once — so a tick counter
# would advance faster in the tab than in the status bar and the two would
# disagree.
IDLE_AFTER_SECONDS=3

# A line longer than this is prose, not an interactive prompt.
MAX_PROMPT_LENGTH=120

# State has to survive between invocations: tmux re-runs these scripts from
# scratch on every status refresh. Keyed by socket path because pane ids
# (%0, %1, ...) are only unique within a single tmux server.
_state_dir=""

agent_state_dir() {
	if [ -z "$_state_dir" ]; then
		local socket_path
		socket_path="$(tmux display -p '#{socket_path}' 2>/dev/null || true)"
		[ -n "$socket_path" ] || socket_path="default"
		_state_dir="${TMPDIR:-/tmp}/tmux-agent-status-${socket_path//[^A-Za-z0-9._-]/_}"
		[ -d "$_state_dir" ] || mkdir -p "$_state_dir"
	fi
	printf '%s' "$_state_dir"
}

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
	# abort the caller mid-loop.
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

# Classify a pane, refreshing its stored state.
#
# Capture the screen yourself and pass it in if you already have it:
# capture-pane is by far the most expensive call here.
#
# Idempotent within a second. Any caller that notices a changed screen resets
# the idle clock and every caller reading the same state gets the same answer,
# so the interleaving of the tab label and the status bar does not matter.
agent_state() {
	local pane_id="$1"
	local screen="${2-}"
	[ -n "$screen" ] || screen="$(tmux capture-pane -t "$pane_id" -p 2>/dev/null || true)"

	local file prev_hash last_change now hash elapsed state
	local rec_hash rec_change rec_state rec_extra
	file="$(agent_state_dir)/${pane_id#\%}"
	now="$(date +%s)"

	prev_hash=""
	last_change=$now
	if [ -f "$file" ]; then
		# Require exactly three well-formed fields. A short record means the
		# file was caught mid-write, or was written by a different version of
		# this script — and misreading it is worse than ignoring it: a stale
		# streak counter landing in last_change looks like an ancient epoch
		# and would mark every pane idle.
		rec_hash=""
		rec_change=""
		rec_state=""
		rec_extra=""
		read -r rec_hash rec_change rec_state rec_extra <"$file" || true

		if [ -z "$rec_extra" ] &&
			[ -n "$rec_state" ] &&
			[ -n "$rec_hash" ] && [ -n "$rec_change" ] &&
			[ -z "${rec_hash//[0-9]/}" ] && [ -z "${rec_change//[0-9]/}" ]; then
			prev_hash="$rec_hash"
			last_change="$rec_change"
		fi
	fi

	hash="$(printf '%s' "$screen" | cksum)"
	hash="${hash%% *}"

	elapsed=$((now - last_change))
	[ "$elapsed" -lt 0 ] && elapsed=0

	if agent_waiting_prompt "$screen"; then
		# A live prompt means the agent is blocked, not idle.
		state=waiting
		last_change=$now
	elif [ "$hash" != "$prev_hash" ]; then
		# The screen moved, so the agent did something.
		state=working
		last_change=$now
	elif [ "$elapsed" -ge "$IDLE_AFTER_SECONDS" ]; then
		state=idle
	else
		state=working
	fi

	printf '%s %s %s\n' "$hash" "$last_change" "$state" >"$file"
	printf '%s' "$state"
}

# Read the last recorded state without touching the pane, so pane-label.sh can
# mirror the status bar for free instead of capturing and hashing on every
# rename. Prints nothing when agent-state.sh has never seen this pane.
agent_state_cached() {
	local file rec_hash rec_change state rec_extra
	file="$(agent_state_dir)/${1#\%}"
	[ -f "$file" ] || return 0
	rec_hash=""
	rec_change=""
	rec_extra=""
	state=""
	read -r rec_hash rec_change state rec_extra <"$file" || true
	[ -z "$rec_extra" ] || return 0
	printf '%s' "$state"
}