#!/bin/bash
# agent-state.sh — Agent state detection for the tmux status bar.
#
# Scans all panes for running coding agents and reports their state:
#   ●/○ name  – agent is actively working (1 fps blink, same clock as tabs)
#   ⌨ name  – agent is blocked on a prompt, waiting for user input
#   ◌ name  – agent is idle: screen unchanged for IDLE_AFTER_SECONDS
#
# Called from status-right via #() expansion every status-interval.

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agents.sh
. "$CURRENT_DIR/agents.sh"
# shellcheck source=state.sh
. "$CURRENT_DIR/state.sh"
# shellcheck source=notify.sh
. "$CURRENT_DIR/notify.sh"

# One-shot AI label: minimum visible-screen size to consider, and growth
# since first sighting required before firing label-gen.sh exactly once per
# pane. Env-overridable for tests (`LABEL_MIN_GROWTH=100 ...`). Visible
# screens run ~2-10k chars, so growth must fit inside that headroom.
LABEL_MIN_BYTES="${LABEL_MIN_BYTES:-750}"
LABEL_MIN_GROWTH="${LABEL_MIN_GROWTH:-750}"
LABEL_GEN="$CURRENT_DIR/label-gen.sh"

# maybe_fire_label <pane-id> <screen>
#
# Tracks per-pane output growth and forks label-gen.sh the first time it
# passes the threshold. The .labelfired marker is written BEFORE forking, so
# the generator runs exactly once whether it succeeds or fails. Silent on
# every error path — the tab keeps its detected name. Never fails.
maybe_fire_label() {
	# AI labels disabled for now — delete this line to re-enable.
	return 0
	local pane_id="$1"
	local screen="$2"
	local dir key bytes base fired meta
	dir="$(agent_state_dir)"
	key="${pane_id#%}"
	fired="$dir/$key.labelfired"
	meta="$dir/$key.labelmeta"
	[ -e "$fired" ] && return 0
	bytes="${#screen}"
	[ "$bytes" -ge "$LABEL_MIN_BYTES" ] || return 0
	if [ ! -f "$meta" ]; then
		printf '%s\n' "$bytes" >"$meta" 2>/dev/null || true
		return 0
	fi
	base="$(cat "$meta" 2>/dev/null || true)"
	case "$base" in
		'' | *[!0-9]*) printf '%s\n' "$bytes" >"$meta" 2>/dev/null || true; return 0 ;;
	esac
	# Screen cleared since baseline — re-baseline, don't fire on stale delta.
	if [ "$bytes" -lt "$base" ]; then
		printf '%s\n' "$bytes" >"$meta" 2>/dev/null || true
		return 0
	fi
	[ "$((bytes - base))" -ge "$LABEL_MIN_GROWTH" ] || return 0
	: >"$fired" 2>/dev/null || return 0
	if [ -x "$LABEL_GEN" ]; then
		# nohup (not setsid: absent on macOS) + closed stdio so the
		# tmux #() caller never blocks on the child.
		nohup "$LABEL_GEN" "$pane_id" </dev/null >/dev/null 2>&1 & disown 2>/dev/null || true
	fi
	return 0
}

output=""
agent_panes=""

while read -r pane_id cmd; do
	[ -z "$cmd" ] && continue

	name="$(agent_name "$pane_id" "$cmd")"
	[ -n "$name" ] || continue

	agent_panes="$agent_panes ${pane_id#\%} "

	# One capture feeds both the prompt heuristic and the change detector.
	screen="$(tmux capture-pane -t "$pane_id" -p 2>/dev/null || true)"

	prev_state="$(agent_state_cached "$pane_id")"
	new_state="$(agent_state "$pane_id" "$screen" "$name")"

	case "$new_state" in
		waiting) icon="$WAITING_ICON" ;;
		idle) icon="$IDLE_ICON" ;;
		*) icon="$(agent_working_frame)" ;;
	esac

	# Notify only on working -> waiting | idle. Empty prev means cold start
	# (plugin just loaded); same-state repeats stay silent.
	if [ "$prev_state" = "working" ] && [ "$new_state" != "working" ]; then
		case "$new_state" in
			waiting | idle) notify_agent_event "$new_state" "$name" "$pane_id" || true ;;
		esac
	fi

	output="$output ${icon} ${name}"

	maybe_fire_label "$pane_id" "$screen" || true

done < <(tmux list-panes -a -F '#{pane_id} #{pane_current_command}' 2>/dev/null || true)

# Forget panes that no longer run an agent. The glob is not a subshell, and rm
# only forks when there is something to remove. Label bookkeeping
# (<id>.labelmeta, <id>.labelfired) is keyed the same way and pruned here so
# a future pane reusing the window starts fresh.
dir="$(agent_state_dir)"
for state_file in "$dir"/*; do
	[ -e "$state_file" ] || continue
	base="${state_file##*/}"
	key="${base%%.*}"
	case "$agent_panes" in
		*" $key "*) continue ;;
	esac
	rm -f "$state_file"
done

# Strip the leading space without spawning sed.
printf '%s\n' "${output# }"