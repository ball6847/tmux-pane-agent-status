# tmux-pane-agent-status

Live status labels in tmux window tabs and status bar — see at a glance which panes have a
running coding agent (⟳), which are idle at a shell prompt (⌄), which have an
editor open (✎), and more.

Also detects when an agent is **waiting for your input** (⌨) and shows it on the
status bar.

## Demo

| State | Window tab | Status bar | Meaning |
|---|---|---|---|
| Working | `⟳ opencode` | `⟳opencode` | Agent is actively running / processing |
| Waiting | `⟳ opencode` | `⌨opencode` | Agent prompted for input ([y/N], Continue?, etc.) |
| Idle | `⌄ bash` | *(empty)* | No agent running in any pane |
| Editor | `✎ nvim` | — | Editing a file |

Status bar example with multiple agent sessions:

```
⟳oc  ⌨cdx  ⟳cl                              | 23:42 16-Jun-26
```

You see at a glance: opencode working, codex waiting for input, claude working.

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
| `opencode` | `⟳ opencode` | Mach-O binary |
| `claude` | `⟳ claude` | Bun-compiled binary |
| `codex` | `⟳ codex` | Mach-O binary |
| `cursor-agent` | `⟳ cursor-agent` | Compiled binary |
| `agy` | `⟳ agy` | Mach-O binary |
| `grok` | `⟳ grok` | Mach-O binary |
| `agent` | `⟳ agent` | Mach-O binary |
| `cr`, `coderabbit` | `⟳ cr` / `⟳ coderabbit` | Mach-O binary |
| `hermes` | `⟳ hermes` | Python-based (detected via PID) |
| `SuperClaude` | `⟳ SuperClaude` | Python-based (detected via PID) |

A trailing `.exe` is stripped before matching, so agents that ship a
Windows-named binary on Unix are still recognised. `opencode`'s npm package,
for instance, installs `opencode-ai/bin/opencode.exe`, which tmux reports as
`opencode.exe`.

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

## Status bar integration

`scripts/agent-state.sh` (also available as `tmux-agent-state` if installed to
`PATH`) scans **all panes** for agent sessions and reports their state on the
`status-right`.

### State detection

| State | Icon | How it's detected |
|---|---|---|
| Working | ⟳ | Agent process is running, no wait prompt detected |
| Waiting | ⌨ | Final non-empty line of the pane looks like a prompt |

Only the **last non-empty line** of the pane is inspected, and it has to look
like a prompt:

1. It contains a known confirmation pattern — `[y/N]`, `[Y/n]`, `[Y/N]`,
   `[y/n]`, `Continue?`, `Proceed?`, `Overwrite? (y/n):`, `Press Enter`, or
   `Press any key`.
2. Or it **ends with `?`**, once trailing whitespace and prompt decorations
   (`>`, `❯`, `›`, `$`, `#`) are stripped — and is at most 120 characters, so
   prose is not mistaken for a question.

Both rules matter. Matching on "contains a `?`" anywhere in the last 3 lines
reported most actively-working panes as waiting, because a `?` two lines up is
almost always leftover prose rather than a live prompt. A prompt that has
already scrolled up likewise means the agent moved on.

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
The classifier script maps command names to icon+label pairs. For Python-based
agents, it additionally checks the pane PID's full command line via `ps`.

**Status bar:** `agent-state.sh` iterates all open panes, identifies agent
processes, and runs a lightweight `capture-pane` heuristic to distinguish
"working" from "waiting for input". Runs once per `status-interval` (15s default).

## Adding an agent

Add its binary name to `AGENT_BINARIES` in `scripts/agents.sh`, or — for an
agent that runs under Python — a `<ps substring>:<display name>` pair to
`AGENT_PYTHON_PATTERNS`. Both scripts pick it up; nothing else needs editing.

## Agent support matrix

| Agent | Type | Tab label | Status bar |
|---|---|---|---|
| opencode | Compiled binary | ⟳ opencode | ⟳ / ⌨ |
| claude | Bun-compiled | ⟳ claude | ⟳ / ⌨ |
| codex | Compiled binary | ⟳ codex | ⟳ / ⌨ |
| cursor-agent | Compiled binary | ⟳ cursor-agent | ⟳ / ⌨ |
| agy | Compiled binary | ⟳ agy | ⟳ / ⌨ |
| grok | Compiled binary | ⟳ grok | ⟳ / ⌨ |
| agent | Compiled binary | ⟳ agent | ⟳ / ⌨ |
| cr / coderabbit | Compiled binary | ⟳ cr / ⟳ coderabbit | ⟳ / ⌨ |
| hermes | Python (venv) | ⟳ hermes | ⟳ / ⌨ |
| SuperClaude | Python (pipx) | ⟳ SuperClaude | ⟳ / ⌨ |
