---
name: tmux-status
description: 查看或重置 tmux session 的 Claude 状态指示。用于状态卡住时手动恢复。
argument-hint: [reset]
allowed-tools: [Bash]
---

# tmux-status

查看或重置当前 tmux session 的 Claude Code 状态指示。

## 用法

- `/tmux-status` — 显示当前 session 的状态（running/waiting/permission/idle）
- `/tmux-status reset` — 清除状态指示，恢复原始 session 名

## 实现

如果参数为 `reset`，运行：

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/claude-tmux-status.sh" idle
```

否则，运行以下命令显示当前状态：

```bash
echo "Session: $(tmux display-message -p '#S')"
echo "Status: $(tmux show-option -qv @claude_status 2>/dev/null || echo 'idle')"
echo "Base name: $(tmux show-option -qv @claude_base_name 2>/dev/null || echo 'N/A')"
```
