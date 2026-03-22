# claude-tmux

[English](README.md) | [中文](README.zh-CN.md)

在 tmux 会话列表中可视化 Claude Code 运行状态的插件。

```
  ⊞ ask-ai
  ⊞ obsidian
  ⚡ brain_storm       ← Claude 正在执行
  💬 learning-space    ← Claude 等待输入
  🔐 ai-builder        ← Claude 等待授权
  ⊞ testcase           ← 无 Claude 运行
```

## 为什么需要

在 tmux 中同时运行多个 Claude Code 会话时，你无法判断哪个需要关注，除非逐个切换查看。这个插件在会话名前添加状态图标，让你一眼看清：

| 图标 | 状态 | 含义 | 需要操作？ |
|------|------|------|-----------|
| ⚡ | 运行中 | Claude 正在处理 | 不需要 |
| 💬 | 等待输入 | Claude 完成了，轮到你 | 需要 |
| 🔐 | 等待授权 | Claude 遇到权限弹窗 | 最紧急 |
| _(无)_ | 空闲 | Claude 已退出 | — |

兼容任何 tmux 配置。推荐搭配 [sesh](https://github.com/joshmedeski/sesh) 使用。

## 安装

在 Claude Code 中运行：

```
/plugin marketplace add Wingsdh/claude-tmux
/plugin install claude-tmux
```

重启 Claude Code，hooks 自动生效。

## 工作原理

插件通过 Claude Code hooks 检测状态变化：

| Hook | 触发时机 | 设置状态 |
|------|---------|---------|
| `PreToolUse` | Claude 调用任何工具 | ⚡ 运行中 |
| `Stop` | Claude 完成响应 | 💬 等待输入 |
| `PermissionRequest` | 权限对话框出现 | 🔐 等待授权 |
| `SessionEnd` | Claude 退出 | _(空闲，恢复原名)_ |

脚本会重命名 tmux session（添加图标前缀）并改变活动窗格的边框颜色。

## 配置

### 配置文件

创建 `~/.config/claude-tmux/config`：

```bash
# 状态图标（支持 emoji、nerd font、纯文本）
ICON_RUNNING="⚡"
ICON_WAITING="💬"
ICON_PERMISSION="🔐"
ICON_IDLE=""

# 窗格边框颜色（hex 或 tmux 颜色名）
BORDER_RUNNING="#a3be8c"
BORDER_WAITING="#88c0d0"
BORDER_PERMISSION="#bf616a"
BORDER_IDLE=""
```

### 预设主题

在配置文件中引用内置预设：

```bash
# ~/.config/claude-tmux/config
source "$PLUGIN_ROOT/presets/nerd-font.conf"

# 引用后可覆盖个别值
BORDER_RUNNING="#50fa7b"
```

可用预设：

| 预设名 | 运行中 | 等待输入 | 等待授权 | 适用场景 |
|--------|-------|---------|---------|----------|
| `default` | ⚡ | 💬 | 🔐 | 通用，所有终端 |
| `circles` | 🟢 | 🔵 | 🔴 | 红绿灯风格 |
| `minimal` | ◉ | ○ | ◈ | 低调几何 |
| `text` | `[RUN]` | `[WAIT]` | `[AUTH]` | 不支持 emoji 的终端 |
| `nerd-font` |  |  |  | Nerd Font 用户 |

### 环境变量

临时覆盖，优先级最高：

```bash
CLAUDE_TMUX_ICON_RUNNING="🔥" claude
```

### 优先级

```
环境变量 > ~/.config/claude-tmux/config > 插件默认值
```

## Skill 命令

插件包含 `/tmux-status` 斜杠命令：

- `/tmux-status` — 查看当前会话状态
- `/tmux-status reset` — 清除状态，恢复原始会话名

## 可选：tmux 快捷键封装

在 `~/.tmux.conf` 中添加，Claude 退出时自动恢复会话名：

```bash
bind C-c new-window -n "cc" -c "#{pane_current_path}" \
  "~/.claude/plugins/claude-tmux/scripts/claude-tmux.sh waiting && claude --model sonnet; ~/.claude/plugins/claude-tmux/scripts/claude-tmux.sh idle"
```

## 推荐：sesh

[sesh](https://github.com/joshmedeski/sesh) 是一个带 fzf 集成的 tmux 会话管理器。状态图标会直接显示在 sesh 的会话选择器中，方便你快速定位需要关注的会话。

不装 sesh 也完全可以用——任何 tmux 会话列表（`prefix + s`、`tmux ls` 等）都会显示图标。

## 许可证

MIT
