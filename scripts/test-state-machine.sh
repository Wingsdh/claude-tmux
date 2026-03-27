#!/usr/bin/env bash
# 测试 claude-tmux 二维状态机
#
# 在隔离的临时 tmux session 中运行，避免当前 Claude Code hooks 干扰
# 用法: bash scripts/test-state-machine.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_TMUX="$SCRIPT_DIR/claude-tmux.sh"
TEST_SESSION="claude-tmux-test-$$"
RESULT_FILE=$(mktemp)

[ ! -x "$CLAUDE_TMUX" ] && chmod +x "$CLAUDE_TMUX"

# ── 测试内容（在临时 session 内执行）─────────────────────

run_tests() {
cat << 'TESTSCRIPT'
#!/usr/bin/env bash
set -euo pipefail

CLAUDE_TMUX="__CLAUDE_TMUX__"
RESULT_FILE="__RESULT_FILE__"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0

# ── 辅助函数 ─────────────────────────────────────────────

get_status()   { tmux show-option -qv @claude_status 2>/dev/null; }
get_pane()     { tmux show-option -qv @claude_pane 2>/dev/null; }
get_base()     { tmux show-option -qv @claude_base_name 2>/dev/null; }
get_visual()   { tmux show-option -qv @claude_visual 2>/dev/null; }
get_session()  { tmux display-message -p '#S'; }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC} $label (= \"$actual\")"
    ((PASS++))
  else
    echo -e "  ${RED}FAIL${NC} $label: expected \"$expected\", got \"$actual\""
    ((FAIL++))
  fi
}

assert_empty() {
  local label="$1" actual="$2"
  if [ -z "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC} $label (empty)"
    ((PASS++))
  else
    echo -e "  ${RED}FAIL${NC} $label: expected empty, got \"$actual\""
    ((FAIL++))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo -e "  ${GREEN}PASS${NC} $label (contains \"$needle\")"
    ((PASS++))
  else
    echo -e "  ${RED}FAIL${NC} $label: \"$haystack\" does not contain \"$needle\""
    ((FAIL++))
  fi
}

ensure_clean() {
  tmux set-option -u @claude_status 2>/dev/null || true
  tmux set-option -u @claude_pane 2>/dev/null || true
  tmux set-option -u @claude_base_name 2>/dev/null || true
  tmux set-option -u @claude_visual 2>/dev/null || true
  tmux set-option -u pane-active-border-style 2>/dev/null || true
  tmux set-hook -gu 'pane-focus-in[1000]' 2>/dev/null || true
  tmux set-hook -gu 'pane-focus-out[1000]' 2>/dev/null || true
}

ORIGINAL_SESSION=$(tmux display-message -p '#S')

echo -e "${YELLOW}测试 claude-tmux 二维状态机${NC}"
echo "Session: $ORIGINAL_SESSION (隔离环境)"
echo ""

# ── 测试 1: running 状态 ─────────────────────────────────

echo "== 测试 1: running 状态 =="
ensure_clean

echo "" | "$CLAUDE_TMUX" running

assert_eq "status" "running" "$(get_status)"
assert_eq "pane 已记录" "$TMUX_PANE" "$(get_pane)"
assert_contains "session 名含 ⚡" "⚡" "$(get_session)"
assert_eq "base_name" "$ORIGINAL_SESSION" "$(get_base)"
echo ""

# ── 测试 2: running 去重 ─────────────────────────────────

echo "== 测试 2: running 重复调用（去重）=="

echo "" | "$CLAUDE_TMUX" running

assert_eq "状态不变" "running" "$(get_status)"
assert_contains "session 名仍含 ⚡" "⚡" "$(get_session)"
echo ""

# ── 测试 3: running → waiting（focused）──────────────────

echo "== 测试 3: running → waiting (pane focused) =="

echo "" | "$CLAUDE_TMUX" waiting

assert_eq "status" "waiting" "$(get_status)"
# 当前 pane 是活跃的，waiting+focused → 不显示图标
assert_eq "session 名无图标（focused）" "$ORIGINAL_SESSION" "$(get_session)"
echo ""

# ── 测试 4: waiting → permission ─────────────────────────

echo "== 测试 4: waiting → permission =="

echo "" | "$CLAUDE_TMUX" permission

assert_eq "status" "permission" "$(get_status)"
assert_contains "session 名含 🔐" "🔐" "$(get_session)"
echo ""

# ── 测试 5: permission → running ─────────────────────────

echo "== 测试 5: permission → running（用户授权后）=="

echo "" | "$CLAUDE_TMUX" running

assert_eq "status" "running" "$(get_status)"
assert_contains "session 名含 ⚡" "⚡" "$(get_session)"
echo ""

# ── 测试 6: idle 彻底清理 ────────────────────────────────

echo "== 测试 6: idle 彻底清理 =="

echo "" | "$CLAUDE_TMUX" idle

assert_empty "status 已清除" "$(get_status)"
assert_empty "pane 已清除" "$(get_pane)"
assert_empty "base_name 已清除" "$(get_base)"
assert_empty "visual 已清除" "$(get_visual)"
assert_eq "session 名恢复" "$ORIGINAL_SESSION" "$(get_session)"
echo ""

# ── 测试 7: idle 去重 ────────────────────────────────────

echo "== 测试 7: idle 重复调用（去重）=="

echo "" | "$CLAUDE_TMUX" running
echo "" | "$CLAUDE_TMUX" idle
echo "" | "$CLAUDE_TMUX" idle  # 第二次应直接退出

assert_empty "status 仍为空" "$(get_status)"
assert_eq "session 名正确" "$ORIGINAL_SESSION" "$(get_session)"
echo ""

# ── 测试 8: refresh 命令 ─────────────────────────────────

echo "== 测试 8: refresh（waiting + focused）=="
ensure_clean

echo "" | "$CLAUDE_TMUX" waiting

"$CLAUDE_TMUX" refresh

assert_eq "status 仍是 waiting" "waiting" "$(get_status)"
assert_eq "session 名无图标（focused）" "$ORIGINAL_SESSION" "$(get_session)"
echo ""

# ── 测试 9: hook 注册与清理 ──────────────────────────────

echo "== 测试 9: hook 注册与清理 =="
ensure_clean

echo "" | "$CLAUDE_TMUX" running

HOOK_IN=$(tmux show-hooks -g 2>/dev/null | grep 'pane-focus-in\[1000\]' || true)
HOOK_OUT=$(tmux show-hooks -g 2>/dev/null | grep 'pane-focus-out\[1000\]' || true)
if [ -n "$HOOK_IN" ] && [ -n "$HOOK_OUT" ]; then
  echo -e "  ${GREEN}PASS${NC} focus hooks 已注册"
  ((PASS++))
else
  echo -e "  ${RED}FAIL${NC} focus hooks 未注册 (in='$HOOK_IN' out='$HOOK_OUT')"
  ((FAIL++))
fi

echo "" | "$CLAUDE_TMUX" idle

HOOK_IN=$(tmux show-hooks -g 2>/dev/null | grep 'pane-focus-in\[1000\]' || true)
HOOK_OUT=$(tmux show-hooks -g 2>/dev/null | grep 'pane-focus-out\[1000\]' || true)
if [ -z "$HOOK_IN" ] && [ -z "$HOOK_OUT" ]; then
  echo -e "  ${GREEN}PASS${NC} focus hooks 已清理"
  ((PASS++))
else
  echo -e "  ${RED}FAIL${NC} focus hooks 未清理"
  ((FAIL++))
fi
echo ""

# ── 测试 10: 完整生命周期 ────────────────────────────────

echo "== 测试 10: 完整生命周期 =="
ensure_clean

echo "" | "$CLAUDE_TMUX" running      # PreToolUse
assert_eq "1. running" "running" "$(get_status)"

echo "" | "$CLAUDE_TMUX" running      # PreToolUse 去重
assert_eq "2. running 去重" "running" "$(get_status)"

echo "" | "$CLAUDE_TMUX" permission   # PermissionRequest
assert_eq "3. permission" "permission" "$(get_status)"

echo "" | "$CLAUDE_TMUX" running      # 授权后继续
assert_eq "4. running" "running" "$(get_status)"

echo "" | "$CLAUDE_TMUX" waiting      # Stop
assert_eq "5. waiting" "waiting" "$(get_status)"

echo "" | "$CLAUDE_TMUX" running      # 用户新输入 → PreToolUse
assert_eq "6. running" "running" "$(get_status)"

echo "" | "$CLAUDE_TMUX" waiting      # Stop
assert_eq "7. waiting" "waiting" "$(get_status)"

echo "" | "$CLAUDE_TMUX" idle         # SessionEnd
assert_empty "8. idle" "$(get_status)"
assert_eq "9. session 恢复" "$ORIGINAL_SESSION" "$(get_session)"
echo ""

# ── 汇总 ─────────────────────────────────────────────────

ensure_clean

echo "================================"
echo -e "结果: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo "================================"

# 写结果到文件供外层读取
echo "$PASS $FAIL" > "$RESULT_FILE"
TESTSCRIPT
}

# ── 执行：创建临时 session 运行测试 ──────────────────────

# 生成测试脚本到临时文件
TEST_SCRIPT=$(mktemp)
run_tests | sed "s|__CLAUDE_TMUX__|$CLAUDE_TMUX|g;s|__RESULT_FILE__|$RESULT_FILE|g" > "$TEST_SCRIPT"
chmod +x "$TEST_SCRIPT"

# 创建隔离的 detached session 并执行测试
tmux new-session -d -s "$TEST_SESSION" -x 120 -y 40 "bash '$TEST_SCRIPT'; sleep 1"

# 等待测试完成（最多 30 秒）
for i in $(seq 1 60); do
  if [ -s "$RESULT_FILE" ]; then
    break
  fi
  if ! tmux has-session -t "$TEST_SESSION" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

# 捕获测试输出
OUTPUT=$(tmux capture-pane -t "$TEST_SESSION" -p 2>/dev/null || true)

# 清理临时 session
tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
rm -f "$TEST_SCRIPT"

# 输出结果
echo "$OUTPUT"

# 读取结果
if [ -s "$RESULT_FILE" ]; then
  read -r PASS FAIL < "$RESULT_FILE"
  rm -f "$RESULT_FILE"
  [ "${FAIL:-1}" -eq 0 ] && exit 0 || exit 1
else
  echo "错误: 测试超时或未产生结果"
  rm -f "$RESULT_FILE"
  exit 1
fi
