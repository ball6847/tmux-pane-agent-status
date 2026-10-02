#!/bin/bash
# pane-label.sh — Classify a tmux pane's foreground command into a status label.
#
# Called from tmux automatic-rename-format via #() expansion.
# Maps pane_current_command to icons for at-a-glance awareness:
#   ●/○ agent   = coding agent actively running (opencode, claude, codex, cursor)
#   ◌ shell   = idle at shell prompt (bash, zsh, fish)
#   ✎ editor  = editor open (nvim, vim, nano)
#   ⚡ dev     = dev tool running (node, npm, bun)
#   🔨 build   = build tool running (make, cargo, go)
#   🌐 remote  = ssh session
#   📊 monitor = system monitoring (htop, top, btm)
#   🔒 sudo    = privileged command
#   🐳 docker  = container tool
#   📄 pager   = less, more, man
#   📋 log     = tail, watch
#   🐍 python  = python process (no agent match)
#   otherwise  = raw command name as fallback
#
# Usage:
#   pane-label.sh <pane-id>

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agents.sh
. "$CURRENT_DIR/agents.sh"
# shellcheck source=state.sh
. "$CURRENT_DIR/state.sh"

pane_id="${1:?usage: pane-label.sh <pane-id>}"
cmd=$(tmux display -t "$pane_id" -p '#{pane_current_command}' 2>/dev/null || true)

# Guard: pane gone or command unreadable
if [ -z "$cmd" ]; then
	echo "?"
	exit 0
fi

# A manual window name (rename-window, stashed in @tab_name by
# tab-name-hook.sh) replaces the detected name but keeps the icon, so a tab
# can read "● asd" instead of "● pi".
custom="$(tmux display -t "$pane_id" -p '#{@tab_name}' 2>/dev/null || true)"

# A coding agent outranks every generic category below, and carries the same
# working / waiting / idle state as the status bar.
agent=$(agent_name "$pane_id" "$cmd")
if [ -n "$agent" ]; then
	# Manual rename wins. AI one-shot label (@ai_label) disabled for now —
	# tab falls back to the detected binary name.
	if [ -n "$custom" ]; then
		agent="$custom"
	fi
	# Mirror the state agent-state.sh already recorded. This format is
	# evaluated several times per status-interval, so it must stay cheap;
	# only compute from scratch if nothing has been recorded yet.
	state="$(agent_state_cached "$pane_id")"
	[ -n "$state" ] || state="$(agent_state "$pane_id" "" "$agent")"
	case "$state" in
		waiting) echo "$WAITING_ICON $agent" ;;
		idle) echo "$IDLE_ICON $agent" ;;
		*) echo "$(agent_working_frame) $agent" ;;
	esac
	exit 0
fi

label="$(agent_normalize_cmd "$cmd")"
# The custom name replaces the printed name, but classification below must
# still see the real command.
cmd_label="$label"
label="${custom:-$label}"

case "$cmd_label" in
	# Shells — idle, waiting at prompt
	bash | sh | zsh | fish) echo "◌ $label" ;;

	# Editors
	nvim | vim | nano | micro) echo "✎ $label" ;;

	# Dev tooling running
	node | npm | npx | bun | deno) echo "⚡ $label" ;;

	# Build tooling running
	make | cargo | go | rustc | just) echo "🔨 $label" ;;

	# Remote sessions
	ssh | mosh | telnet) echo "🌐 $label" ;;

	# System monitoring / paging
	htop | top | btm | bpytop | bashtop) echo "📊 $label" ;;
	less | more | man) echo "📄 $label" ;;

	# Privilege escalation
	sudo | doas) echo "🔒 $label" ;;

	# Containers
	docker | docker-compose | podman) echo "🐳 $label" ;;

	# Python without an agent match
	python | python3) echo "🐍 $label" ;;

	# Tmux itself (status line processes etc.)
	tmux) echo "⏎" ;;

	# Logs / tailing
	tail | tailf | watch) echo "📋 $label" ;;

	# Generic fallback — show the command as reported by tmux
	*) echo "$label" ;;
esac