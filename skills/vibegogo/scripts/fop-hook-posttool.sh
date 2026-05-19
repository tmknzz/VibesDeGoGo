#!/bin/bash
# fop-hook-posttool.sh — PostToolUse hook（Bash エラー検出してフラグ作成）
# C 案: 検出後、次の PreToolUse で「【エラー認識】」テキストを強制要求

set -euo pipefail

INPUT=$(cat)

if ! command -v jq &> /dev/null; then
    # jq 不在時はフェイルクローズ（安全側ブロック）。ただし jq 導入そのもの（狭い
    # セットアップ系ホワイトリスト）だけは素通しし、復旧経路を塞がない。
    FALLBACK_TOOL=$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
    FALLBACK_CMD=$(printf '%s' "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/')
    if command -v brew &> /dev/null; then
        ( brew install jq > /tmp/fop-jq-install.log 2>&1 & )
        echo "fop-hook-posttool: jq not found. Auto-installing in background (brew install jq, log: /tmp/fop-jq-install.log)。" >&2
    else
        echo "fop-hook-posttool: jq required but brew not found. Install jq manually." >&2
    fi
    if [ "$FALLBACK_TOOL" = "Bash" ] && printf '%s' "$FALLBACK_CMD" | grep -qE 'brew[[:space:]]+(install|reinstall)([[:space:]]|[^|;&])*[[:space:]]jq([[:space:]]|$)'; then
        exit 0
    fi
    echo "fop-hook-posttool: jq 不在のため安全側でブロック（fail-close）。jq を導入してから再実行してください。" >&2
    exit 2
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
HOOK_EVENT_NAME=$(echo "$INPUT" | jq -r '.hook_event_name // empty')

# CWD を取得
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$CWD" ]; then
    exit 0
fi

# active file から現在のVibeGoGo ID を取得
ACTIVE_FILE="$CWD/.claude/.fop-active"
if [ ! -f "$ACTIVE_FILE" ]; then
    exit 0
fi

FON_ID=$(cat "$ACTIVE_FILE")
if [ -z "$FON_ID" ]; then
    exit 0
fi

# ID に対応する state file を読む
STATE_FILE="$CWD/.claude/.fop-state-${FON_ID}"
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(grep "^phase=" "$STATE_FILE" | cut -d= -f2 || true)
STEP=$(grep "^step=" "$STATE_FILE" | cut -d= -f2 || true)
LOOP_COUNT=$(grep "^loop_count=" "$STATE_FILE" | cut -d= -f2 || true)
LOOP_COUNT="${LOOP_COUNT:-0}"

if [ -z "$PHASE" ]; then
    exit 0
fi

# ---- phase ごとの tool フィルタ ----
# testing 以外: 既存の Bash エラー検出のみが意味を持つ。Bash 以外は exit 0。
# testing: Bash / Skill / Edit / Write を通す（後続 T3/T4 で simplify sentinel 等を追加）。
#          それ以外（Read/Glob/Grep/Agent 等）は exit 0。
if [ "$PHASE" != "testing" ]; then
    if [ "$TOOL_NAME" != "Bash" ]; then
        exit 0
    fi
else
    case "$TOOL_NAME" in
        Bash|Skill|Edit|Write)
            ;;
        *)
            exit 0
            ;;
    esac
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // 0')
STDERR=$(echo "$INPUT" | jq -r '.tool_response.stderr // empty')
STDOUT=$(echo "$INPUT" | jq -r '.tool_response.stdout // empty')
HOOK_ERROR=$(echo "$INPUT" | jq -r '.error // empty')

# TODO(T3/T4): testing phase の simplify sentinel 処理は以降のブロックで追加する。
#              tool_name が Skill/Edit/Write のとき Bash エラー検出は無意味なので
#              下の Bash エラー検出ブロックには進ませず、ここから先で testing 専用の
#              ロジックに分岐させる予定（T3 implementer が組み込む）。

# ---- T3: simplify Skill 起動検出 → sentinel 生成（testing phase 限定） ----
# Skill tool で simplify が呼ばれたら .fop-simplify-sentinel-{id}-{loop_count} を生成。
# 既存があれば started_at を維持（再起動でも初回時刻を残す）。
# T4 で追加予定の Edit/Write 検出ブロックに進む前に exit 0 で終わる（Skill 経路は完結）。
if [ "$PHASE" = "testing" ] && [ "$TOOL_NAME" = "Skill" ]; then
    SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')
    if [ "$SKILL_NAME" = "simplify" ]; then
        SENTINEL_FILE="$CWD/.claude/.fop-simplify-sentinel-${FON_ID}-${LOOP_COUNT}"
        if [ ! -f "$SENTINEL_FILE" ]; then
            STARTED_AT=$(date -u +%FT%TZ)
            cat > "$SENTINEL_FILE" <<EOF
started=1
started_at=${STARTED_AT}
modified=0
modified_files=
EOF
        fi
        exit 0
    fi
fi

# ---- T4: simplify 起動後の Edit/Write 検出 → sentinel に modified=1 記録 ----
# testing phase 限定。sentinel が既に存在する（= simplify 起動済み）場合のみ作用する。
# state file 自体 / .fop-active / tasks/fop/<id>/ 配下の編集は記録対象外（VibeGoGo管理ファイル）。
# investigation.md §5.6 妥協案: simplify 起動後の Edit/Write はすべて reflection 経由扱いとする。
if [ "$PHASE" = "testing" ] && { [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; }; then
    SENTINEL_FILE="$CWD/.claude/.fop-simplify-sentinel-${FON_ID}-${LOOP_COUNT}"
    if [ -f "$SENTINEL_FILE" ]; then
        EDITED_FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
        # VibeGoGo 管理ファイル（state file / active file）は記録対象外
        if [[ "$EDITED_FILE_PATH" == *"/.fop-state-"* ]] || [[ "$EDITED_FILE_PATH" == *"/.fop-active"* ]]; then
            exit 0
        fi
        # tasks/fop/<id>/ 配下（progress.md 等の管理ファイル）は記録対象外
        TASKS_DIR_BASENAME="tasks/fop/${FON_ID}"
        if [[ "$EDITED_FILE_PATH" == *"$TASKS_DIR_BASENAME"* ]]; then
            exit 0
        fi
        # modified_files に重複追加しないよう既存リストを確認
        CURRENT_FILES=$(grep '^modified_files=' "$SENTINEL_FILE" | head -1 | sed 's/^modified_files=//')
        if [ -n "$EDITED_FILE_PATH" ] && [[ ",$CURRENT_FILES," != *",$EDITED_FILE_PATH,"* ]]; then
            if [ -z "$CURRENT_FILES" ]; then
                NEW_FILES="$EDITED_FILE_PATH"
            else
                NEW_FILES="${CURRENT_FILES},${EDITED_FILE_PATH}"
            fi
        else
            NEW_FILES="$CURRENT_FILES"
        fi
        # sentinel から modified= / modified_files= 行を削除して再書き込み（atomic）
        TMP=$(mktemp)
        grep -v '^modified=' "$SENTINEL_FILE" | grep -v '^modified_files=' > "$TMP" || true
        cat >> "$TMP" <<EOF
modified=1
modified_files=${NEW_FILES}
EOF
        mv "$TMP" "$SENTINEL_FILE"
        exit 0
    fi
fi

if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

# ---- 誤検知防止: 検索系コマンドの exit 1 は「マッチなし」として無視 ----
SEARCH_CMDS_PATTERN='(^|[[:space:];&|(])(grep|rg|ag|ack|find|awk|sed|fgrep|egrep|jq|test|\[)([[:space:]]|$)'
IS_SEARCH=0
if echo "$COMMAND" | grep -qE "$SEARCH_CMDS_PATTERN"; then
    IS_SEARCH=1
fi

# ---- 誤検知防止: フォーメーション skill 内部コマンドは見ない ----
# fo*_state_* 関数呼び出しは内部状態管理、エラー扱い不要
if echo "$COMMAND" | grep -qE 'fo[a-z]_state_(init|write|advance|loop|clear|read)'; then
    exit 0
fi

# ---- エラー検出 ----
ERROR_DETECTED=0
ERROR_REASON=""

if [ "$EXIT_CODE" -ne 0 ]; then
    # 検索系の exit 1 は「マッチなし」として無視（exit 2 以上は実エラー）
    if [ "$IS_SEARCH" -eq 1 ] && [ "$EXIT_CODE" -lt 2 ]; then
        :  # 無視
    else
        ERROR_DETECTED=1
        ERROR_REASON="exit code=$EXIT_CODE"
    fi
fi

if [ "$ERROR_DETECTED" -eq 0 ] && [ "$HOOK_EVENT_NAME" = "PostToolUseFailure" ]; then
    ERROR_DETECTED=1
    if [ -n "$HOOK_ERROR" ]; then
        ERROR_REASON="$HOOK_ERROR"
    else
        ERROR_REASON="PostToolUseFailure"
    fi
fi

# stderr に error / fail パターン（検索系は除外、stderr が出力結果になることがある）
if [ "$ERROR_DETECTED" -eq 0 ] && [ "$IS_SEARCH" -eq 0 ]; then
    if echo "$STDERR" | grep -qE '(^|[^a-zA-Z])(error|Error|ERROR|fail|Fail|FAIL|Exception|Traceback|エラー|失敗)([^a-zA-Z]|$)'; then
        ERROR_DETECTED=1
        ERROR_REASON="stderr に error/fail/Exception/エラー/失敗 パターン検出"
    fi
fi

# stdout の行頭 error: / fail: のみ対象（grep 結果の "error log" 等は無視）
if [ "$ERROR_DETECTED" -eq 0 ] && [ "$IS_SEARCH" -eq 0 ]; then
    if echo "$STDOUT" | grep -qE '^[[:space:]]*(error|Error|ERROR|fail|Fail|FAIL|エラー|失敗):[[:space:]]'; then
        ERROR_DETECTED=1
        ERROR_REASON="stdout 行頭に error: / fail: パターン検出"
    fi
fi

# ---- フラグ作成 ----
if [ "$ERROR_DETECTED" -eq 1 ]; then
    FLAG_FILE="$CWD/.claude/.fop-error-pending"
    {
        echo "reason=$ERROR_REASON"
        echo "command=$COMMAND"
        echo "exit_code=$EXIT_CODE"
        if [ -n "$STDERR" ]; then
            echo "stderr_excerpt=$(echo "$STDERR" | head -c 500)"
        else
            echo "stderr_excerpt=$(echo "$HOOK_ERROR" | head -c 500)"
        fi
    } > "$FLAG_FILE"
fi

exit 0
