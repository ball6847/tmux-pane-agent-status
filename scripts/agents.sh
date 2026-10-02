#!/usr/bin/env bash
# agents.sh — canonical list of AI coding agents recognised by this plugin.
#
# Sourced by pane-label.sh and agent-state.sh so the two cannot drift apart.
# Previously each script carried its own copy of the list, so an agent could
# get a tab label without ever showing up in the status bar.

# Agents distributed as a compiled binary: pane_current_command matches the
# name directly. Space separated.
AGENT_BINARIES="opencode claude codex cursor cursor-agent agy grok agent cr coderabbit pi"

# Agents that run under the python interpreter: pane_current_command reports
# plain `python`/`python3`, so the real name is recovered by matching the
# pane PID's full command line. Format: "<ps substring>:<display name>".
AGENT_PYTHON_PATTERNS="hermes:hermes SuperClaude:SuperClaude"

# Agents whose state comes from the external `asd` tool (agent-status-detect)
# instead of the screen-change heuristic in state.sh. Format: "<display name>:<asd tool name>".
AGENT_ASD_TOOLS="pi:pi"

# Some agents ship a Windows-named binary on Unix — opencode's npm package, for
# example, installs opencode-ai/bin/opencode.exe, so tmux reports
# `opencode.exe` as the foreground command. Strip the suffix before matching.
agent_normalize_cmd() {
	local cmd="${1:-}"
	printf '%s' "${cmd%.exe}"
}

# agent_asd_tool <display name>
#
# Prints the `asd` tool name when this agent's state should be detected by
# `asd`, otherwise prints nothing. Never fails.
agent_asd_tool() {
	local pair
	for pair in $AGENT_ASD_TOOLS; do
		if [ "$1" = "${pair%%:*}" ]; then
			printf '%s' "${pair#*:}"
			return 0
		fi
	done
	return 0
}

# agent_pane_runs_pi <pane-id>
#
# pi is a node script, so pane_current_command reports `node` and the binary
# name check above never fires. Recover the real name from the pane's process
# table: pi sets its process title, so `ps` shows a bare `pi` as argv[0]; a
# direct ./pi or full-path invocation leaves the script path there instead.
agent_pane_runs_pi() {
	local tty row first tok
	tty="$(tmux display -t "$1" -p '#{pane_tty}' 2>/dev/null || true)"
	[ -n "$tty" ] || return 1
	while read -r row; do
		[ -n "$row" ] || continue
		first="${row%% *}"
		case "$first" in
			pi | */pi) return 0 ;;
			node | node.exe | bun | deno)
				for tok in $row; do
					case "$tok" in
						*/pi) return 0 ;;
					esac
				done
				;;
		esac
	done < <(ps -t "$tty" -o args= 2>/dev/null || true)
	return 1
}

# agent_name <pane-id> <pane_current_command>
#
# Prints the display name if the pane runs a known coding agent, otherwise
# prints nothing and returns 0. Never fails, so callers can use it as a filter.
agent_name() {
	local _pane_id="$1"
	local cmd
	cmd="$(agent_normalize_cmd "${2:-}")"
	[ -n "$cmd" ] || return 0

	local binary
	for binary in $AGENT_BINARIES; do
		if [ "$cmd" = "$binary" ]; then
			printf '%s' "$cmd"
			return 0
		fi
	done

	# pi runs under the node interpreter but has no interpreter entry below:
	# check the pane's process table before giving up on `node`/`bun`.
	if [ "$cmd" = "node" ] || [ "$cmd" = "node.exe" ] || [ "$cmd" = "bun" ] || [ "$cmd" = "deno" ]; then
		if agent_pane_runs_pi "$_pane_id"; then
			printf 'pi'
		fi
		return 0
	fi

	if [ "$cmd" != "python" ] && [ "$cmd" != "python3" ]; then
		return 0
	fi

	local pid full_cmd pattern needle
	pid="$(tmux display -t "$_pane_id" -p '#{pane_pid}' 2>/dev/null || true)"
	[ -n "$pid" ] || return 0
	full_cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
	[ -n "$full_cmd" ] || return 0

	for pattern in $AGENT_PYTHON_PATTERNS; do
		needle="${pattern%%:*}"
		case "$full_cmd" in
			*"$needle"*)
				printf '%s' "${pattern#*:}"
				return 0
				;;
		esac
	done

	return 0
}