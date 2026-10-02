# tmux-pane-agent-status

Live status labels in tmux window tabs and status bar — see at a glance which panes have a
running coding agent (●/○), which are waiting on you (⌨), which are sitting idle
at their prompt (◌), which have an editor open (✎), and more.

## Demo

| State | Window tab | Status bar | Meaning |
|---|---|---|---|
| Working | `●/○ opencode` | `●/○ opencode` | Agent is actively running / redrawing |
| Waiting | `⌨ opencode` | `⌨ opencode` | Agent prompted for input ([y/N], Continue?, etc.) |
| Idle | `◌ opencode` | `◌ opencode` | Agent alive but screen has stopped changing |
| No agent | `⌄ bash` | *(empty)* | Pane is at a shell prompt |
| Editor | `✎ nvim` | — | Editing a file |

The window tab and the status bar always report the same state for the same
agent, with the same `icon name` spacing.

Status bar example with multiple agent sessions:

```
◌ oc  ⌨ cdx  ● cl                             | 23:42 16-Jun-26
```

You see at a glance: opencode finished and is idle, codex is waiting for
input, claude is still working.

## Quick start

### Via TPM (recommended)

Add to `~/.tmux.conf`:

```tmux
set -g @plugin 'duyet/tmux-pane-agent-status'
run-shell '~/.tmux/plugins/tpm/tpm'
```

`<prefix> + I` installs the plugin. Labels appear immediately on next window
split.

### Manual

```bash
git clone https://github.com/duyet/tmux-pane-agent-status ~/.tmux/plugins/tmux-pane-agent-status
```

The entry point is a shell script, so run it rather than `source-file`:

```tmux
run-shell '~/.tmux/plugins/tmux-pane-agent-status/tmux-pane-agent-status.tmux'
```

### Standalone (tab labels only)

Copy `scripts/pane-label.sh` to somewhere in `$PATH`
(e.g. `~/.local/bin/tmux-pane-label`) and add to `~/.tmux.conf`:

```tmux
set -g automatic-rename-format \
  "#{?pane_in_mode,[tmux],#(tmux-pane-label #{pane_id})}#{?pane_dead,[dead],}"
bind R set-window-option automatic-rename on \; display "Dynamic naming ON"
```

## Tab label reference

Window tab names (`automatic-rename-format`) show what's running in the active
pane:

### AI coding agents

| Process name | Tab label | Notes |
|---|---|---|
| `opencode` | `● opencode` | Mach-O binary |
| `claude` | `● claude` | Bun-compiled binary |
| `codex` | `● codex` | Mach-O binary |
| `cursor-agent` | `● cursor-agent` | Compiled binary |
| `agy` | `● agy` | Mach-O binary |
| `grok` | `● grok` | Mach-O binary |
| `agent` | `● agent` | Mach-O binary |
| `cr`, `coderabbit` | `● cr` / `● coderabbit` | Mach-O binary |
| `hermes` | `● hermes` | Python-based (detected via PID) |
| `SuperClaude` | `● SuperClaude` | Python-based (detected via PID) |
| `pi` | `● pi` | Node script (detected via process table) |

A trailing `.exe` is stripped before matching, so agents that ship a
Windows-named binary on Unix are still recognised. `opencode`'s npm package,
for instance, installs `opencode-ai/bin/opencode.exe`, which tmux reports as
`opencode.exe`.

`pi` runs as a node script, so tmux reports `node` as the foreground command
and the name is recovered from the pane's process table instead: pi shows up
there as a bare `pi` (it sets its process title) or as a path ending in `/pi`.

For agents the icon is not fixed: it follows the agent's working / waiting /
idle state described below, so the tab reads `⌨ opencode` when it needs you and
`◌ opencode` when it has finished.

The list lives in `scripts/agents.sh`, shared by both scripts so an agent can
never gain a tab label without also appearing in the status bar.

### Everything else

| Foreground command | Tab label | Meaning |
|---|---|---|
| `bash`, `sh`, `zsh`, `fish` | `⌄ name` | Idle at shell prompt |
| `nvim`, `vim`, `nano`, `micro` | `✎ name` | Editor open |
| `node`, `npm`, `npx`, `bun`, `deno` | `⚡ name` | Dev tool running |
| `python`, `python3` | `🐍 python` | Python process (no agent match) |
| `ssh`, `mosh`, `telnet` | `🌐 name` | Remote session |
| `htop`, `top`, `btm`, `bpytop`, `bashtop` | `📊 name` | System monitor |
| `docker`, `docker-compose`, `podman` | `🐳 name` | Container tool |
| `sudo`, `doas` | `🔒 name` | Privileged command |
| `make`, `cargo`, `go`, `rustc`, `just` | `🔨 name` | Build tool |
| `less`, `more`, `man` | `📄 name` | Pager |
| `tail`, `tailf`, `watch` | `📋 name` | Log follow |
| `tmux` | `⏎` | Tmux internal |
| anything else | raw command | Fallback |

### Custom tab names

Rename a window (`prefix + ,` or `tmux rename-window`) and the tab keeps its
status icon: the chosen name simply replaces the detected one, so the window
renamed to `asd` reads `● asd`. The name is stored in the window's `@tab_name`
option and dynamic naming is re-enabled automatically (a plain rename would
freeze the tab without any icon).

Rename to an empty name to clear it, or press `prefix + R`, which drops the
custom name and returns to fully dynamic naming (`● pi`).

## Status bar integration

`scripts/agent-state.sh` (also available as `tmux-agent-state` if installed to
`PATH`) scans **all panes** for agent sessions and reports their state on the
`status-right`.

### State detection

| State | Icon | How it's detected |
|---|---|---|
| Waiting | ⌨ | Final non-empty line of the pane looks like a prompt |
| Working | ●/○ | Agent process is running and its screen is still changing |
| Idle | ◌ | Agent process is running but its screen has not changed recently |

For `pi` panes the verdict comes from `asd` (agent-status-detect) instead:
`asd --tool pi` reads pi's own UI and prints `running` / `waiting` / `idle`,
which map to ●/○ / ⌨ / ◌. `asd` is optional — resolved via `command -v asd`
with a `~/.local/bin/asd` fallback — and without it pi uses the heuristics
below like every other agent.

### Waiting

Only the **last non-empty line** of the pane is inspected, and it has to look
like a prompt:

1. It contains a known confirmation pattern — `[y/N]`, `[Y/n]`, `[Y/N]`,
   `[y/n]`, `Continue?`, `Proceed?`, `Overwrite? (y/n):`, `Press Enter`, or
   `Press any key`.
2. Or it **ends with `?`**, once trailing whitespace and prompt decorations
   (`>`, `❯`, `›`, `$`, `#`) are stripped — and is at most 120 characters, so
   prose is not mistaken for a question.

Both rules matter. Matching on "contains a `?`" anywhere in the pane reported
most actively-working panes as waiting, because a `?` a couple of lines up is
almost always leftover prose rather than a live prompt. A prompt that has
already scrolled up likewise means the agent moved on.

### Idle

`pane_current_command` only tells you *which* program is running, never whether
it is busy. A finished agent is still the foreground process, and a full-screen
TUI does not return to a shell prompt when it is done — so a naive check keeps
reporting `●` forever.

Idle is therefore detected by **change**, not by content: the visible screen of
each agent pane is hashed on every tick and compared with the previous tick. If
it comes back byte-identical after `IDLE_AFTER_SECONDS`, the agent is idle.
This needs no per-agent knowledge, so it works for TUIs and line-oriented CLIs
alike.

Waiting outranks idle, so a pane sitting on a prompt stays `⌨` instead of
decaying to `◌`.

Idle is measured in wall-clock seconds rather than ticks. tmux evaluates
`automatic-rename-format` more often than `status-interval`, so a tick counter
would advance faster in the tab label than in the status bar and the two would
drift apart.

Raise `IDLE_AFTER_SECONDS` for agents that sit still for a while while still
working. Screen hashes are kept between ticks under
`${TMPDIR:-/tmp}/tmux-agent-status-<socket>`, since tmux re-runs the scripts from
scratch on every refresh. State for panes that stop being agents is pruned.

### Keeping the two in sync

Both entry points read the state module in `scripts/state.sh`, so the tab label
and the status bar cannot disagree. `pane-label.sh` reads back the state
`agent-state.sh` already recorded rather than capturing and hashing again:
`automatic-rename-format` is evaluated several times per `status-interval`, and
that path stays free. If nothing has been recorded yet — because
`agent-state.sh` is not on your `status-right` — it falls back to computing the
state itself.

State records are validated before use: exactly three well-formed fields, or
the record is ignored. A truncated file, or one left by a different version of
the script, must not be half-believed — misreading one is worse than having
none.

### Custom status-right

The plugin overwrites `status-right`. To keep your own layout, drop the plugin's
`set -g status-right` line and call `agent-state.sh` wherever you want:

```tmux
set -g status-right "#(/path/to/tmux-pane-agent-status/scripts/agent-state.sh) | %H:%M %d-%b-%y"
```

## Key bindings

| Binding | Action |
|---|---|
| `<prefix> R` | Re-enable dynamic naming on current window |

Windows renamed with `<prefix> + ,` get `automatic-rename` turned off.
`<prefix> R` turns it back on so the label updates again.

## How it works

**Entry point:** `tmux-pane-agent-status.tmux` is a shell script, because TPM
executes `*.tmux` files instead of handing them to `tmux source-file`. It
resolves its own directory, so the plugin works from any install location
rather than assuming `~/.tmux/plugins`. It sets three things:
`automatic-rename-format`, a `<prefix> R` binding, and `status-right`.

**Tab labels:** Tmux's `automatic-rename-format` dynamically sets window names
based on the active pane's foreground command (`#{pane_current_command}`).
The classifier script maps command names to icon+label pairs, and for agents
attaches the shared state module. For Python-based agents, it additionally
checks the pane PID's full command line via `ps`.

**Status bar:** `agent-state.sh` iterates all open panes, identifies agent
processes, and captures each one's visible screen. One capture feeds both the
prompt heuristic and the change detector. Runs once per `status-interval`.

**Shared:** `scripts/state.sh` holds the state logic and the on-disk records
both entry points read, so the tab and the status bar report one answer.

## Adding an agent

Add its binary name to `AGENT_BINARIES` in `scripts/agents.sh`, or — for an
agent that runs under Python — a `<ps substring>:<display name>` pair to
`AGENT_PYTHON_PATTERNS`. Both scripts pick it up; nothing else needs editing.

To retune detection, edit the constants at the top of `scripts/state.sh`:
`IDLE_AFTER_SECONDS`, `MAX_PROMPT_LENGTH`, and the three icons.

## Agent support matrix

| Agent | Type | Tab label | Status bar |
|---|---|---|---|
| opencode | Compiled binary | ● opencode | ●/○ / ⌨ |
| claude | Bun-compiled | ● claude | ●/○ / ⌨ |
| codex | Compiled binary | ● codex | ●/○ / ⌨ |
| cursor-agent | Compiled binary | ● cursor-agent | ●/○ / ⌨ |
| agy | Compiled binary | ● agy | ●/○ / ⌨ |
| grok | Compiled binary | ● grok | ●/○ / ⌨ |
| agent | Compiled binary | ● agent | ●/○ / ⌨ |
| cr / coderabbit | Compiled binary | ● cr / ● coderabbit | ●/○ / ⌨ |
| hermes | Python (venv) | ● hermes | ●/○ / ⌨ |
| SuperClaude | Python (pipx) | ● SuperClaude | ●/○ / ⌨ |
