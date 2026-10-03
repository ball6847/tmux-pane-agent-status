#!/usr/bin/env bash
# notify.sh — desktop notifications for agent state transitions.
#
# macOS-first, portable by design. One entry point:
#   notify_agent_event <prev-state> <new-state> <agent-name> [pane-id]
# Strict edge trigger: notifies ONLY on working -> waiting | idle; every
# other transition (cold start, repeats, idle/waiting -> *, * -> working)
# is a silent no-op. Requires state.sh alongside for the arming marker.
# Sourced by agent-state.sh. Never fails (returns 0) so `set -e` callers
# keep rendering the status bar even when notification fails.
#
# Titles read what the tab reads: the window's @tab_name custom name when
# set (see tab-name-hook.sh), otherwise the detected agent name.

# Set to 0 / empty to silence: `tmux set -g @agent_notify_off 1`
# or `TMUX_AGENT_NOTIFY=0`.
_notify_enabled() {
	local opt
	[ -n "${TMUX_AGENT_NOTIFY-}" ] && [ "$TMUX_AGENT_NOTIFY" = "0" ] && return 1
	opt="$(tmux show-option -gqv @agent_notify_off 2>/dev/null || true)"
	[ "$opt" = "1" ] && return 1
	return 0
}

# Sound name (macOS system sound: Ping, Glass, Hero, ...).
# `tmux set -g @agent_notify_sound Glass`, or
# `TMUX_AGENT_NOTIFY_SOUND=Glass`. Empty or `none` = silent.
_notify_sound() {
	if [ -n "${TMUX_AGENT_NOTIFY_SOUND-}" ]; then
		printf '%s' "$TMUX_AGENT_NOTIFY_SOUND"
		return 0
	fi
	local opt
	opt="$(tmux show-option -gqv @agent_notify_sound 2>/dev/null || true)"
	if [ -n "$opt" ]; then
		printf '%s' "$opt"
	else
		printf 'Ping'
	fi
}

# Escape a string for embedding in an AppleScript double-quoted literal.
_osascript_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Build the osascript argument: with or without `sound name`.
_osa_message() {
	local title="$1" msg="$2" sound="$3"
	if [ -n "$sound" ]; then
		printf 'display notification "%s" with title "%s" sound name "%s"' \
			"$(_osascript_escape "$msg")" "$(_osascript_escape "$title")" "$sound"
	else
		printf 'display notification "%s" with title "%s"' \
			"$(_osascript_escape "$msg")" "$(_osascript_escape "$title")"
	fi
}

# Generic sender with per-OS fallback chain. Override the command used via
# $TMUX_AGENT_NOTIFIER: terminal-notifier | osascript | notify-send | tmux.
_notify_send() {
	local title="$1" msg="$2"
	local force os sound osa_msg
	force="${TMUX_AGENT_NOTIFIER-}"
	os="$(uname 2>/dev/null || printf 'unknown')"
	sound="$(_notify_sound)"
	case "$sound" in "" | none | NONE) sound="" ;; esac

	if [ -n "$force" ]; then
		case "$force" in
			terminal-notifier)
				command -v terminal-notifier >/dev/null 2>&1 || return 0
				if [ -n "$sound" ]; then
					terminal-notifier -title "$title" -message "$msg" -sound "$sound" >/dev/null 2>&1 || true
				else
					terminal-notifier -title "$title" -message "$msg" >/dev/null 2>&1 || true
				fi
				return 0
				;;
			osascript)
				[ "$os" = "Darwin" ] || return 0
				osa_msg="$(_osa_message "$title" "$msg" "$sound")"
				osascript -e "$osa_msg" >/dev/null 2>&1 || true
				return 0
				;;
			notify-send)
				command -v notify-send >/dev/null 2>&1 || return 0
				notify-send "$title" "$msg" >/dev/null 2>&1 || true
				return 0
				;;
			tmux)
				tmux display-message "$title: $msg" >/dev/null 2>&1 || true
				return 0
				;;
		esac
	fi

	# Auto: richest available first, tmux message as last resort.
	if command -v terminal-notifier >/dev/null 2>&1; then
		if [ -n "$sound" ]; then
			terminal-notifier -title "$title" -message "$msg" -sound "$sound" >/dev/null 2>&1 || true
		else
			terminal-notifier -title "$title" -message "$msg" >/dev/null 2>&1 || true
		fi
		return 0
	fi
	if [ "$os" = "Darwin" ]; then
		osa_msg="$(_osa_message "$title" "$msg" "$sound")"
		osascript -e "$osa_msg" >/dev/null 2>&1 || true
		return 0
	fi
	if command -v notify-send >/dev/null 2>&1; then
		notify-send "$title" "$msg" >/dev/null 2>&1 || true
		return 0
	fi
	tmux display-message "$title: $msg" >/dev/null 2>&1 || true
	return 0
}

# _notify_title <icon> <fallback-name> [pane-id] -> "<icon> <name>"
#
# The notification title uses the current tab name: @tab_name when the tab
# was renamed (prefix + ,), else the detected agent name — the same
# precedence pane-label.sh uses, so the popup matches the tab.
_notify_title() {
	local icon="$1" fallback="${2-}" pane_id="${3-}" tab=""
	if [ -n "$pane_id" ]; then
		tab="$(tmux display -t "$pane_id" -p '#{@tab_name}' 2>/dev/null || true)"
	fi
	if [ -n "$tab" ]; then
		printf '%s %s' "$icon" "$tab"
	else
		printf '%s %s' "$icon" "$fallback"
	fi
}

# notify_agent_event <prev-state> <new-state> <agent-name> [pane-id]
#
# Fires only on working -> waiting | idle, and only when the working
# episode was armed by observed activity (agent_state touches the .armed
# marker on a real screen change / `asd running` verdict). The marker is
# consumed here, so each running episode notifies at most once and repeats
# stay silent. Old 3-arg callers (new-state first) safely stay silent:
# their first arg lands in <prev-state> and fails the working check.
notify_agent_event() {
	local prev="${1-}" state="${2-}" name="${3-}" pane_id="${4-}"
	_notify_enabled || return 0
	[ "$prev" = "working" ] || return 0
	case "$state" in
		waiting | idle) ;;
		*) return 0 ;;
	esac
	if command -v agent_state_dir >/dev/null 2>&1; then
		local armed
		armed="$(agent_state_dir)/${pane_id#\%}.armed"
		[ -f "$armed" ] || return 0
		rm -f "$armed"
	fi
	case "$state" in
		waiting)
			_notify_send "$(_notify_title "⌨" "$name" "$pane_id")" "Agent is waiting for your input"
			;;
		idle)
			_notify_send "$(_notify_title "◌" "$name" "$pane_id")" "Agent has finished the task, please check"
			;;
	esac
	return 0
}
