#!/bin/bash
# fop-hook-stop.sh — Stop hook（VibeGoGo サイクル中の "うっかり停止" を物理強制ブロック）
#
# 動作:
#   - VibeGoGo state file がアクティブな状態でターン終了しようとしたとき発火
#   - 最終 assistant ターンに以下のいずれも無ければ exit 2 でブロック:
#       1. tool_use の Bash command 内に fop_state_(advance|loop|write|clear|init) 呼び出し
#       2. assistant text 内に「【意図的停止】」明示
#   - state file 無し → exit 0 で素通し
#   - stop_hook_active=true → 無限ループ防止のため exit 0
#
# cwd の取得:
#   Stop hook の入力 JSON に cwd が含まれない可能性があるため、
#   transcript_path の親ディレクトリを辿って .claude/.fop-active を持つディレクトリを探す。
#   ただし transcript は ~/.claude/projects/<encoded-cwd>/*.jsonl に置かれるので、
#   encoded-cwd から実際の cwd を復元する。

set -euo pipefail

INPUT=$(cat)

if ! command -v jq &> /dev/null; then
    exit 0  # jq 無しでは動けないが、エージェント停止は阻害しない
fi

# 無限ループ防止
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# cwd を取得（Stop hook の入力に cwd フィールドがあるはず）。
# transcript_path からの逆算は `/` ↔ `-` エンコードのため、ハイフン入りパス（例: TimeCamera-）で
# 復元できない。誤った CWD を返すリスクを避けるため、cwd 無しの場合は素通し（exit 0）にする。
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    exit 0
fi

# active file から現在のVibeGoGo ID 取得
ACTIVE_FILE="$CWD/.claude/.fop-active"
if [ ! -f "$ACTIVE_FILE" ]; then
    exit 0
fi

FON_ID=$(cat "$ACTIVE_FILE")
if [ -z "$FON_ID" ]; then
    exit 0
fi

STATE_FILE="$CWD/.claude/.fop-state-${FON_ID}"
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(grep "^phase=" "$STATE_FILE" | cut -d= -f2 || true)
STEP=$(grep "^step=" "$STATE_FILE" | cut -d= -f2 || true)

# 現ターン assistant メッセージ群を取得（最後の user message より後の assistant 行群）
LAST_USER_LINE=$(jq -r 'select(.type=="user" and ((.message.content | type) == "string" or ((.message.content | type) == "array" and (.message.content[0].type // "") != "tool_result"))) | input_line_number' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)
LAST_USER_LINE="${LAST_USER_LINE:-0}"

# テキスト部分（意図的停止検出用）
CURRENT_TURN_TEXT=$(awk -v start="$LAST_USER_LINE" 'NR > start' "$TRANSCRIPT_PATH" \
    | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text // empty' 2>/dev/null || true)

# tool_use の Bash command 部分（advance 等の検出用）
CURRENT_TURN_BASH=$(awk -v start="$LAST_USER_LINE" 'NR > start' "$TRANSCRIPT_PATH" \
    | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Bash") | .input.command // empty' 2>/dev/null || true)

# Bash command に fop_state_(advance|loop|write|clear|init) があれば進行中
if echo "$CURRENT_TURN_BASH" | grep -qE 'fop_state_(advance|loop|write|clear|init)'; then
    exit 0
fi

# テキストに 【意図的停止】 があれば許可
if echo "$CURRENT_TURN_TEXT" | grep -qF "【意図的停止】"; then
    exit 0
fi

# どちらもなし → ブロック
echo "VibeGoGo [${FON_ID}] step=${STEP} phase=${PHASE}: 進行中なのに fop_state_(advance|loop|write|clear|init) を呼ばずに終わろうとしています。次のアクションを実行（advance/loop/clear のいずれか）するか、user確認待ち等で意図的に止まる場合は assistant text に「【意図的停止】<理由>」を明示してください" >&2
exit 2
