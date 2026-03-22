#!/usr/bin/env bash
# claude-tmux — 根据 Claude Code 状态改变 tmux session 外观
#
# 用法: claude-tmux.sh <running|waiting|permission|idle>

set -euo pipefail

# 不在 tmux 中则静默退出
[ -z "${TMUX:-}" ] && exit 0

# 消费 stdin（Claude Code hook 会传入 JSON）
# 用 timeout 避免无 stdin 时阻塞
timeout 1 cat > /dev/null 2>&1 || true

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

# ── 状态管理 ──────────────────────────────────────────────

# 用 @claude_base_name 存原始 session 名，避免去前缀的兼容性问题
BASE_NAME=$(tmux show-option -qv @claude_base_name 2>/dev/null)
if [ -z "$BASE_NAME" ]; then
  BASE_NAME=$(tmux display-message -p '#S')
  tmux set-option @claude_base_name "$BASE_NAME"
fi

CURRENT=$(tmux show-option -qv @claude_status 2>/dev/null)

set_status() {
  local status="$1" icon="$2" border="$3"

  # 跳过重复设置
  [ "$CURRENT" = "$status" ] && exit 0

  tmux set-option @claude_status "$status"

  # 更新 session 名
  if [ -n "$icon" ]; then
    tmux rename-session "$icon $BASE_NAME"
  else
    tmux rename-session "$BASE_NAME"
  fi

  # 更新 pane border 颜色
  if [ -n "$border" ]; then
    tmux set-option pane-active-border-style "fg=$border"
  else
    tmux set-option -u pane-active-border-style 2>/dev/null || true
  fi
}

case "${1:-}" in
  running)
    set_status "running" "$ICON_RUNNING" "$BORDER_RUNNING"
    ;;
  waiting)
    set_status "waiting" "$ICON_WAITING" "$BORDER_WAITING"
    ;;
  permission)
    set_status "permission" "$ICON_PERMISSION" "$BORDER_PERMISSION"
    ;;
  idle)
    tmux set-option -u @claude_status 2>/dev/null || true
    tmux set-option -u @claude_base_name 2>/dev/null || true
    tmux rename-session "$BASE_NAME"
    tmux set-option -u pane-active-border-style 2>/dev/null || true
    ;;
  *)
    echo "Usage: claude-tmux.sh <running|waiting|permission|idle>" >&2
    exit 1
    ;;
esac

exit 0
