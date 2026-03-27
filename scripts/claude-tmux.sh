#!/usr/bin/env bash
# claude-tmux — 二维状态机：Claude 真实状态 × 用户 pane 焦点
#
# 用法: claude-tmux.sh <running|waiting|permission|idle|refresh>
#   running/waiting/permission/idle — Claude Code hooks 驱动
#   refresh — pane 焦点变化时回调，仅重算显示

set -euo pipefail

# 不在 tmux 中则静默退出
[ -z "${TMUX:-}" ] && exit 0

# 消费 stdin（Claude Code hook 会传入 JSON）
# refresh 命令由 tmux hook 触发，无 stdin
if [ "${1:-}" != "refresh" ]; then
  timeout 1 cat > /dev/null 2>&1 || true
fi

# ── 配置加载 ──────────────────────────────────────────────

# 1. 默认值
ICON_RUNNING="⚡"
ICON_WAITING="💬"
ICON_PERMISSION="🔐"
ICON_IDLE=""

BORDER_RUNNING="#a3be8c"
BORDER_WAITING="#88c0d0"
BORDER_PERMISSION="#bf616a"
BORDER_IDLE=""

# 2. 加载用户配置（如存在）
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/claude-tmux/config"
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && source "$CONFIG"

# 3. 环境变量覆盖（优先级最高）
ICON_RUNNING="${CLAUDE_TMUX_ICON_RUNNING:-$ICON_RUNNING}"
ICON_WAITING="${CLAUDE_TMUX_ICON_WAITING:-$ICON_WAITING}"
ICON_PERMISSION="${CLAUDE_TMUX_ICON_PERMISSION:-$ICON_PERMISSION}"
ICON_IDLE="${CLAUDE_TMUX_ICON_IDLE:-$ICON_IDLE}"

BORDER_RUNNING="${CLAUDE_TMUX_BORDER_RUNNING:-$BORDER_RUNNING}"
BORDER_WAITING="${CLAUDE_TMUX_BORDER_WAITING:-$BORDER_WAITING}"
BORDER_PERMISSION="${CLAUDE_TMUX_BORDER_PERMISSION:-$BORDER_PERMISSION}"
BORDER_IDLE="${CLAUDE_TMUX_BORDER_IDLE:-$BORDER_IDLE}"

# ── 脚本路径（用于 tmux hook 回调）─────────────────────────
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# ── 基础 session 名 ────────────────────────────────────────

strip_icons() {
  # 去除已知状态图标前缀（支持多个叠加的情况）
  local name="$1"
  # 用 shell 内置替换，避免 macOS sed 对 emoji 的兼容问题
  local prev=""
  while [ "$name" != "$prev" ]; do
    prev="$name"
    # 依次尝试剥离每个已知图标前缀（图标+可选空格）
    name="${name#⚡ }" ; name="${name#⚡}"
    name="${name#💬 }" ; name="${name#💬}"
    name="${name#🔐 }" ; name="${name#🔐}"
    # 清理前导空格
    name="${name# }"
  done
  echo "$name"
}

BASE_NAME=$(tmux show-option -qv @claude_base_name 2>/dev/null)
if [ -z "$BASE_NAME" ]; then
  BASE_NAME=$(strip_icons "$(tmux display-message -p '#S')")
  tmux set-option @claude_base_name "$BASE_NAME"
fi

# ── 焦点检测 ──────────────────────────────────────────────

is_pane_focused() {
  local claude_pane
  claude_pane=$(tmux show-option -qv @claude_pane 2>/dev/null)
  [ -n "$claude_pane" ] && \
    [ "$(tmux display-message -p -t "$claude_pane" '#{pane_active}' 2>/dev/null)" = "1" ]
}

# ── 统一显示函数 ──────────────────────────────────────────

# 记录上次渲染的视觉状态，避免重复 tmux 调用
LAST_VISUAL=$(tmux show-option -qv @claude_visual 2>/dev/null)

apply_visual() {
  local icon="$1" border="$2"
  local visual_key="${icon}|${border}"

  # 跳过重复渲染
  [ "$LAST_VISUAL" = "$visual_key" ] && return 0

  tmux set-option @claude_visual "$visual_key"

  # 更新 session 名：从当前名重新计算 base，防止图标叠加
  local clean_name
  clean_name=$(strip_icons "$(tmux display-message -p '#S')")
  if [ -n "$icon" ]; then
    tmux rename-session "$icon $clean_name"
  else
    tmux rename-session "$clean_name"
  fi

  # 更新 pane border 颜色
  if [ -n "$border" ]; then
    tmux set-option pane-active-border-style "fg=$border"
  else
    tmux set-option -u pane-active-border-style 2>/dev/null || true
  fi
}

update_display() {
  local status
  status=$(tmux show-option -qv @claude_status 2>/dev/null)

  case "$status" in
    running)
      apply_visual "$ICON_RUNNING" "$BORDER_RUNNING"
      ;;
    waiting)
      if is_pane_focused; then
        apply_visual "" ""  # 用户在场：不显示
      else
        apply_visual "$ICON_WAITING" "$BORDER_WAITING"  # 不在场：提醒
      fi
      ;;
    permission)
      apply_visual "$ICON_PERMISSION" "$BORDER_PERMISSION"
      ;;
    *)
      apply_visual "" ""
      ;;
  esac
}

# ── Hook 注册/清理 ────────────────────────────────────────

register_focus_hooks() {
  tmux set-hook -g 'pane-focus-in[1000]' \
    "run-shell \"${SCRIPT_PATH} refresh\""
  tmux set-hook -g 'pane-focus-out[1000]' \
    "run-shell \"${SCRIPT_PATH} refresh\""
}

cleanup_all() {
  # 清除焦点 hooks
  tmux set-hook -gu 'pane-focus-in[1000]' 2>/dev/null || true
  tmux set-hook -gu 'pane-focus-out[1000]' 2>/dev/null || true

  # 清除所有 @ 变量
  tmux set-option -u @claude_status 2>/dev/null || true
  tmux set-option -u @claude_pane 2>/dev/null || true
  tmux set-option -u @claude_base_name 2>/dev/null || true
  tmux set-option -u @claude_visual 2>/dev/null || true

  # 恢复视觉
  tmux rename-session "$BASE_NAME"
  tmux set-option -u pane-active-border-style 2>/dev/null || true
}

# ── 入口 ──────────────────────────────────────────────────

case "${1:-}" in
  running|waiting|permission)
    CURRENT=$(tmux show-option -qv @claude_status 2>/dev/null)

    # 状态未变时仅刷新显示（焦点可能变了）
    if [ "$CURRENT" = "$1" ]; then
      update_display
      exit 0
    fi

    tmux set-option @claude_status "$1"
    tmux set-option @claude_pane "${TMUX_PANE:-}"
    register_focus_hooks
    update_display
    ;;
  idle)
    # 去重：已经是 idle 则跳过
    CURRENT=$(tmux show-option -qv @claude_status 2>/dev/null)
    [ -z "$CURRENT" ] && exit 0

    cleanup_all
    ;;
  refresh)
    update_display
    ;;
  *)
    echo "Usage: claude-tmux.sh <running|waiting|permission|idle|refresh>" >&2
    exit 1
    ;;
esac

exit 0
