# claude-tmux

Claude Code plugin that visualizes session status in your tmux session list.

```
  ⊞ ask-ai
  ⊞ obsidian
  ⚡ brain_storm       ← Claude is working
  💬 learning-space    ← Claude is waiting for input
  🔐 ai-builder        ← Claude needs permission
  ⊞ testcase           ← No Claude running
```

## Why

When you run multiple Claude Code sessions in tmux, you can't tell which ones need your attention without switching to each one. This plugin adds status icons to your session names so you know at a glance:

| Icon | Status | Meaning | Action needed? |
|------|--------|---------|---------------|
| ⚡ | Running | Claude is processing | No |
| 💬 | Waiting | Claude finished, your turn | Yes |
| 🔐 | Permission | Claude hit a permission prompt | Urgent |
| _(none)_ | Idle | Claude exited | — |

Works with any tmux setup. Pairs great with [sesh](https://github.com/joshmedeski/sesh).

## Install

In Claude Code, run:

```
/plugin marketplace add Wingsdh/claude-tmux
/plugin install claude-tmux
```

Restart Claude Code. Hooks activate automatically.

## How it works

The plugin uses Claude Code hooks to detect state changes:

| Hook | Triggers | Sets status to |
|------|----------|---------------|
| `PreToolUse` | Claude calls any tool | ⚡ running |
| `Stop` | Claude finishes responding | 💬 waiting |
| `PermissionRequest` | Permission dialog appears | 🔐 permission |
| `SessionEnd` | Claude exits | _(idle, restores original name)_ |

The script renames your tmux session with an icon prefix and changes the active pane border color.

## Configuration

### Config file

Create `~/.config/claude-tmux/config`:

```bash
# Icons (emoji, nerd font, or plain text)
ICON_RUNNING="⚡"
ICON_WAITING="💬"
ICON_PERMISSION="🔐"
ICON_IDLE=""

# Pane border colors (hex or tmux color names)
BORDER_RUNNING="#a3be8c"
BORDER_WAITING="#88c0d0"
BORDER_PERMISSION="#bf616a"
BORDER_IDLE=""
```

### Presets

Use a built-in preset by sourcing it in your config file:

```bash
# ~/.config/claude-tmux/config
source "$PLUGIN_ROOT/presets/nerd-font.conf"

# Override individual values after sourcing
BORDER_RUNNING="#50fa7b"
```

Available presets:

| Preset | Running | Waiting | Permission | Best for |
|--------|---------|---------|------------|----------|
| `default` | ⚡ | 💬 | 🔐 | All terminals |
| `circles` | 🟢 | 🔵 | 🔴 | Traffic light style |
| `minimal` | ◉ | ○ | ◈ | Subtle, geometric |
| `text` | `[RUN]` | `[WAIT]` | `[AUTH]` | No emoji support |
| `nerd-font` |  |  |  | Nerd Font users |

### Environment variables

Override any setting per-session:

```bash
CLAUDE_TMUX_ICON_RUNNING="🔥" claude
```

### Priority

```
Environment variables > ~/.config/claude-tmux/config > Plugin defaults
```

## Skill

The plugin includes a `/tmux-status` slash command:

- `/tmux-status` — Show current session status
- `/tmux-status reset` — Clear status and restore original session name

## Optional: tmux keybinding wrapper

Add to your `~/.tmux.conf` to auto-clear status when Claude exits:

```bash
bind C-c new-window -n "cc" -c "#{pane_current_path}" \
  "~/.claude/plugins/claude-tmux/scripts/claude-tmux.sh waiting && claude --model sonnet; ~/.claude/plugins/claude-tmux/scripts/claude-tmux.sh idle"
```

## Recommended: sesh

[sesh](https://github.com/joshmedeski/sesh) is a tmux session manager with fzf integration. The status icons show up directly in the sesh session picker, making it easy to spot which sessions need attention.

The plugin works without sesh — any tmux session list (`prefix + s`, `tmux ls`, etc.) will show the icons.

## License

MIT
