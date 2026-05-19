#!/bin/bash
# fop-hook-pretool.sh — PreToolUse hook（VibeGoGo Step順序物理強制、ID対応版）

set -euo pipefail

INPUT=$(cat)

if ! command -v jq &> /dev/null; then
    # jq 不在時はフェイルクローズ（安全側ブロック）。ただし jq 導入そのもの（狭い
    # セットアップ系ホワイトリスト）だけは素通しし、復旧経路を塞がない。
    FALLBACK_TOOL=$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
    FALLBACK_CMD=$(printf '%s' "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/')
    if command -v brew &> /dev/null; then
        ( brew install jq > /tmp/fop-jq-install.log 2>&1 & )
        echo "fop-hook-pretool: jq not found. Auto-installing in background (brew install jq, log: /tmp/fop-jq-install.log)。インストール完了後（数秒〜1分）に再度実行してください。" >&2
    else
        echo "fop-hook-pretool: jq required but brew not found. Install jq manually." >&2
    fi
    if [ "$FALLBACK_TOOL" = "Bash" ] && printf '%s' "$FALLBACK_CMD" | grep -qE 'brew[[:space:]]+(install|reinstall)([[:space:]]|[^|;&])*[[:space:]]jq([[:space:]]|$)'; then
        exit 0
    fi
    echo "fop-hook-pretool: jq 不在のため安全側でブロック（fail-close）。jq を導入してから再実行してください。" >&2
    exit 2
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# CWD を取得
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$CWD" ]; then
    exit 0
fi

# active file から現在のVibeGoGo IDを取得
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

# tasks ディレクトリ（ID付き、$CWD 基準の絶対パス）
TASKS_DIR="$CWD/tasks/fop/${FON_ID}"

# ---- ツール種別ごとの情報取得 ----

case "$TOOL_NAME" in
    Edit|Write)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
        ;;
    Bash)
        COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
        ;;
    Agent)
        # Agent は phase によってブロック判定
        ;;
    *)
        # Read, Glob, Grep 等 → 常に許可
        exit 0
        ;;
esac

# ---- エラー認識検証（PostTool でエラー検出後の認識強制）----
ERROR_FLAG="$CWD/.claude/.fop-error-pending"
if [ -f "$ERROR_FLAG" ]; then
    TRANSCRIPT_PATH_E=$(echo "$INPUT" | jq -r '.transcript_path // empty')
    if [ -n "$TRANSCRIPT_PATH_E" ] && [ -f "$TRANSCRIPT_PATH_E" ]; then
        LAST_USER_LINE_E=$(jq -r 'select(.type=="user" and ((.message.content | type) == "string" or ((.message.content | type) == "array" and (.message.content[0].type // "") != "tool_result"))) | input_line_number' "$TRANSCRIPT_PATH_E" 2>/dev/null | tail -1)
        LAST_USER_LINE_E="${LAST_USER_LINE_E:-0}"
        CURRENT_TURN_TEXT_E=$(awk -v start="$LAST_USER_LINE_E" 'NR > start' "$TRANSCRIPT_PATH_E" | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text // empty' 2>/dev/null || true)
        if echo "$CURRENT_TURN_TEXT_E" | grep -qF "【エラー認識】"; then
            rm -f "$ERROR_FLAG"
        else
            ERROR_REASON=$(grep "^reason=" "$ERROR_FLAG" | cut -d= -f2- || echo "不明")
            echo "VibeGoGo [${FON_ID}]: 直前の Bash でエラー検出 ($ERROR_REASON)。次のツール実行前に「【エラー認識】<内容> + 対応方針」テキストを assistant text に出力してください。出力後にこのフラグは自動削除されます" >&2
            exit 2
        fi
    fi
fi

# ---- ガード4: state file (.claude/.fop-state-* / .fop-active) の直接編集ブロック ----
# 全 phase 共通。fop_state_* 関数経由以外での書き換えを禁止
if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
    if [[ "$FILE_PATH" == *"/.claude/.fop-state-"* ]] || [[ "$FILE_PATH" == *"/.claude/.fop-active" ]] \
        || [[ "$FILE_PATH" == *".claude/.fop-state-"* ]] || [[ "$FILE_PATH" == *".claude/.fop-active" ]]; then
        echo "VibeGoGo [${FON_ID}]: state file (.claude/.fop-state-* / .fop-active) の直接編集は禁止。fop_state_* 関数経由で操作してください" >&2
        exit 2
    fi
fi
if [ "$TOOL_NAME" = "Bash" ]; then
    # Bash でも state file を書き換えるコマンド（リダイレクト / tee / sed -i / mv / cp / rm）をブロック
    if echo "$COMMAND" | grep -qE '(\.claude/\.fop-state-|\.claude/\.fop-active)'; then
        # fop_state_* 関数呼び出し or 読み取り用（cat/grep/less/tail/head/source/\.） は許可、それ以外はブロック
        if echo "$COMMAND" | grep -qE '(>|>>|tee[[:space:]]|sed[[:space:]]+-i|mv[[:space:]]|cp[[:space:]]|rm[[:space:]])' \
            && ! echo "$COMMAND" | grep -qE 'fop_state_(init|write|advance|loop|clear)'; then
            echo "VibeGoGo [${FON_ID}]: state file を Bash で直接書き換えることは禁止。fop_state_* 関数経由で操作してください" >&2
            exit 2
        fi
    fi
fi

## ---- ガード2: Step 宣言検証（Bash で phase 遷移コマンドを実行する時）----
# fop_state_advance/loop/write が呼ばれる前に、**Bash コマンド本体**（tool_input.command）に
# target step と一致する宣言コメントが含まれるか検証する。一致しない場合ブロック。
#
# 検証対象を transcript（assistant text）ではなく COMMAND（tool_input.command）に置く理由:
#   - PreToolUse hook 呼び出し時、現メッセージの assistant text は transcript に
#     未書き込みのケースがあり、正規の1回目でも「宣言なし」と誤判定されることがある。
#   - その結果エージェントが2回目以降に同じ Bash を再試行することで通る「すり抜け」が発生し、
#     物理強制が機能しない。
#   - tool_input.command は hook の input に必ず含まれるため、transcript タイミングに
#     依存せず確実に検証できる。1回目で必ず通るので auto mode 完走可能。
#
# 例外: TARGET_STEP=2 のときのみ「【VibeGoGo 宣言】」（Step 1 起動宣言）も許容
#
# エージェントの書き方の例:
#   # 【VibeGoGo Step 3 開始】 step=3, phase=investigating, loop=0
#   source $HOME/.claude/skills/vibegogo/scripts/fop-state.sh && fop_state_advance 3 investigating
#
# 注: assistant text 側の宣言テキストは人間可読・チャット表示用に残すが、
#     hook の検証対象ではない（hook は COMMAND だけを見る）。
if [ "$TOOL_NAME" = "Bash" ] && echo "$COMMAND" | grep -qE 'fop_state_(advance|loop|write)[[:space:]]+[0-9]+'; then
    TARGET_STEP=$(echo "$COMMAND" | sed -nE 's/.*fop_state_(advance|loop|write)[[:space:]]+([0-9]+).*/\2/p' | head -1)
    if [ -n "$TARGET_STEP" ]; then
        DECL_OK=0
        if echo "$COMMAND" | grep -qF "【VibeGoGo Step ${TARGET_STEP} 開始】"; then
            DECL_OK=1
        elif [ "$TARGET_STEP" = "2" ] && echo "$COMMAND" | grep -qF '【VibeGoGo 宣言】'; then
            DECL_OK=1
        fi
        if [ "$DECL_OK" -eq 0 ]; then
            echo "VibeGoGo [${FON_ID}]: Bash コマンド本体に「【VibeGoGo Step ${TARGET_STEP} 開始】」コメントが含まれていません。Bash コマンドの中（例: \`# 【VibeGoGo Step ${TARGET_STEP} 開始】 step=${TARGET_STEP}, phase=..., loop=...\`）に宣言を書いてから fop_state_(advance|loop|write) を呼んでください" >&2
            exit 2
        fi
    fi
fi

# ---- ガード5: implementing phase でのテスト実行ブロック ----
# テスト実行は Step 6 testing に遷移してから行う（phase 統合を防ぐ）
# デフォルトパターンに加え、.fop-target の TEST_COMMAND_PATTERN を追加で評価する
if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "implementing" ]; then
    TEST_PATTERN_DEFAULT='swift[[:space:]]+test|xcodebuild[[:space:]]+[^|]*[[:space:]]test|pytest|npm[[:space:]]+(run[[:space:]]+)?test|pnpm[[:space:]]+(run[[:space:]]+)?test|yarn[[:space:]]+(run[[:space:]]+)?test|go[[:space:]]+test|cargo[[:space:]]+test|jest|vitest|mocha'
    TEST_PATTERN_EXTRA=""
    if [ -f "$CWD/.fop-target" ]; then
        TEST_PATTERN_EXTRA=$(grep '^TEST_COMMAND_PATTERN=' "$CWD/.fop-target" 2>/dev/null | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/' | head -1)
    fi
    TEST_PATTERN="$TEST_PATTERN_DEFAULT"
    if [ -n "$TEST_PATTERN_EXTRA" ]; then
        TEST_PATTERN="${TEST_PATTERN}|${TEST_PATTERN_EXTRA}"
    fi
    if echo "$COMMAND" | grep -qE "(^|[[:space:];&|(])(${TEST_PATTERN})([[:space:]]|$)"; then
        echo "VibeGoGo Step ${STEP} (implementing) [${FON_ID}]: implementing 中のテスト実行は禁止。Step 6 (testing) に遷移してから実行してください" >&2
        exit 2
    fi
fi

# ---- loop_count 上限チェック（implementing/testing phase のみ）----
# Read/Glob/Grep は上の esac で exit 0 済みなのでここには到達しない（自動的に許可）
# Edit/Write/Bash/Agent のみこのチェックを通る
if [ "$PHASE" = "implementing" ] || [ "$PHASE" = "testing" ]; then
    if [ "$LOOP_COUNT" -ge 99 ]; then
        echo "VibeGoGo Step ${STEP} (${PHASE}) [${FON_ID}]: loop_count=${LOOP_COUNT} が上限 99 に到達。エージェントに戻してください（Read/Glob/Grep は許可）" >&2
        exit 2
    fi
fi

# ---- phase に応じたブロック判定 ----

case "$PHASE" in
    declare|requirements)
        # Agent ツールをブロック
        if [ "$TOOL_NAME" = "Agent" ]; then
            echo "VibeGoGo Step ${STEP} [${FON_ID}]: 人間のターンです" >&2
            exit 2
        fi
        # Edit/Write は tasks/fop/{id}/ 配下のみ許可（コード編集禁止）
        if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
            if [ -n "$FILE_PATH" ]; then
                if [[ "$FILE_PATH" == */${TASKS_DIR}/* ]] || [[ "$FILE_PATH" == ${TASKS_DIR}/* ]]; then
                    exit 0
                fi
                echo "VibeGoGo Step ${STEP} (${PHASE}) [${FON_ID}]: ${TASKS_DIR}/ 配下以外のファイル編集は禁止: $FILE_PATH" >&2
                exit 2
            fi
        fi
        # requirements phase で Step 3 (investigating) へ遷移するコマンド実行時、
        # tasks/fop/{id}/requirements.md の存在を必須化
        if [ "$PHASE" = "requirements" ] && [ "$TOOL_NAME" = "Bash" ]; then
            if echo "$COMMAND" | grep -qE 'fop_state_(advance|loop|write)[[:space:]]+3[[:space:]]+investigating([[:space:]]|$)'; then
                REQ_FILE="${TASKS_DIR}/requirements.md"
                if [ ! -f "$REQ_FILE" ]; then
                    echo "VibeGoGo Step ${STEP} (requirements) [${FON_ID}]: ${REQ_FILE} が存在しません。Step 0 でuserと握った Goal / Constraints / Acceptance criteria を、必須見出し3項目（## Goal / ## Constraints / ## Acceptance criteria）で書き出してから investigating に進んでください" >&2
                    exit 2
                fi
            fi
        fi
        ;;

    investigating|planning)
        # Edit/Write は tasks/fop/{id}/ 配下のみ許可（コード編集禁止）
        # 書き手はエージェント／subagentいずれでも可
        if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
            if [ -n "$FILE_PATH" ]; then
                if [[ "$FILE_PATH" == */${TASKS_DIR}/* ]] || [[ "$FILE_PATH" == ${TASKS_DIR}/* ]]; then
                    exit 0
                fi
                echo "VibeGoGo Step ${STEP} (${PHASE}) [${FON_ID}]: ${TASKS_DIR}/ 配下以外のファイル編集は禁止: $FILE_PATH" >&2
                exit 2
            fi
        fi
        ;;

    task-selected)
        # Edit/Write をブロック
        if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
            echo "VibeGoGo Step ${STEP} (task-selected) [${FON_ID}]: ファイル編集は禁止" >&2
            exit 2
        fi
        ;;

    implementing|testing)
        # Bash で git commit を含むコマンドをブロック
        if [ "$TOOL_NAME" = "Bash" ]; then
            if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+commit($|[[:space:]])'; then
                echo "VibeGoGo Step ${STEP} (${PHASE}) [${FON_ID}]: git commit は禁止" >&2
                exit 2
            fi
            # testing → implementing 直接遷移をブロック（reflection 経由を強制）
            if [ "$PHASE" = "testing" ] && echo "$COMMAND" | grep -qE 'fop_state_(loop|advance|write)[[:space:]]+[0-9]+[[:space:]]+implementing'; then
                echo "VibeGoGo Step ${STEP} (testing) [${FON_ID}]: testing → implementing 直接遷移は禁止。fop_state_advance <step> reflection を経由して失敗要因・前回との差分・次の仮説を progress.md に追記してください" >&2
                exit 2
            fi
            # testing → verified 遷移時に simplify sentinel を検証
            if [ "$PHASE" = "testing" ] && echo "$COMMAND" | grep -qE 'fop_state_(advance|loop|write)[[:space:]]+[0-9]+[[:space:]]+verified'; then
                SENTINEL_FILE="$CWD/.claude/.fop-simplify-sentinel-${FON_ID}-${LOOP_COUNT}"
                if [ ! -f "$SENTINEL_FILE" ]; then
                    echo "VibeGoGo Step ${STEP} (testing) [${FON_ID}]: simplify 未起動。fop_state_advance 7 verified の前に simplify Skill を起動して変更コードをレビューしてください（hook が .fop-simplify-sentinel ファイルの存在を検証します）" >&2
                    exit 2
                fi
                MODIFIED=$(grep '^modified=' "$SENTINEL_FILE" | head -1 | sed 's/^modified=//')
                if [ "$MODIFIED" = "1" ]; then
                    MODIFIED_FILES=$(grep '^modified_files=' "$SENTINEL_FILE" | head -1 | sed 's/^modified_files=//')
                    echo "VibeGoGo Step ${STEP} (testing) [${FON_ID}]: simplify が修正を入れたため verified 直接遷移は禁止。修正ファイル: ${MODIFIED_FILES}。fop_state_advance 6 reflection を経由して reflection で「simplify 由来の修正内容と再テストの仮説」を progress.md に追記してから implementing に戻し、再テストしてください" >&2
                    exit 2
                fi
                # ガード通過時に sentinel を削除（次サイクルへ持ち越さない）
                rm -f "$SENTINEL_FILE"
            fi
        fi
        ;;

    reflection)
        # Edit/Write は progress.md と researcher の investigation-r{loop}.md のみ許可（コード編集禁止）
        if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
            if [ -n "$FILE_PATH" ]; then
                if [[ "$FILE_PATH" == "${TASKS_DIR}/progress.md" ]] \
                    || [[ "$FILE_PATH" == "${TASKS_DIR}"/investigation-r*.md ]]; then
                    exit 0
                fi
            fi
            echo "VibeGoGo Step ${STEP} (reflection) [${FON_ID}]: reflection 中は progress.md / investigation-r{loop}.md 以外の編集禁止: ${FILE_PATH:-（未指定）}" >&2
            exit 2
        fi
        # Agent（subagent呼び出し）は許可 — reflection 冒頭で researcher 起動して深く深く調査するため
        # Bash: reflection → implementing 遷移コマンド実行時、progress.md が reflection 中に更新されたかを検証
        if [ "$TOOL_NAME" = "Bash" ]; then
            # reflection → verified 直行は禁止（必ず implementing 経由で再テスト）
            if echo "$COMMAND" | grep -qE 'fop_state_(advance|loop|write)[[:space:]]+[0-9]+[[:space:]]+verified'; then
                echo "VibeGoGo Step ${STEP} (reflection) [${FON_ID}]: reflection → verified 直行は禁止。fop_state で implementing に戻して再テストし、testing→simplify→verified の正規経路を通してください" >&2
                exit 2
            fi
            if echo "$COMMAND" | grep -qE 'fop_state_(loop|advance|write)[[:space:]]+6[[:space:]]+implementing'; then
                PROGRESS_FILE="${TASKS_DIR}/progress.md"
                if [ ! -f "$PROGRESS_FILE" ]; then
                    echo "VibeGoGo reflection [${FON_ID}]: progress.md が存在しません。失敗要因・前回との差分・次の仮説を追記してから implementing に戻してください" >&2
                    exit 2
                fi
                STATE_MTIME=$(stat -f %m "$STATE_FILE" 2>/dev/null || echo 0)
                PROGRESS_MTIME=$(stat -f %m "$PROGRESS_FILE" 2>/dev/null || echo 0)
                if [ "$PROGRESS_MTIME" -le "$STATE_MTIME" ]; then
                    echo "VibeGoGo reflection [${FON_ID}]: reflection 中に progress.md が更新されていません（失敗要因・前回との差分・次の仮説を追記してから implementing に戻す）" >&2
                    exit 2
                fi
            fi
        fi
        ;;

    verified|progress|commit)
        # Edit/Write をブロック（progress / commit は progress.md / .fop-target 指定のバージョンファイルのみ許可、verified は全禁止）
        if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
            if { [ "$PHASE" = "progress" ] || [ "$PHASE" = "commit" ]; } && [ -n "$FILE_PATH" ]; then
                # progress.md（TASKS_DIR は $CWD 基準の絶対パスなので完全一致で十分）
                if [[ "$FILE_PATH" == "${TASKS_DIR}/progress.md" ]]; then
                    exit 0
                fi
                # .fop-target 設定ファイルから VERSION_FILE_*_PATH を拾って許可
                TARGET_FILE="$CWD/.fop-target"
                if [ -f "$TARGET_FILE" ]; then
                    ALLOWED_PATHS=$(grep -E '^VERSION_FILE_[0-9]+_PATH=' "$TARGET_FILE" \
                        | sed -E 's/^[^=]*=//' \
                        | sed -E 's/^"(.*)"$/\1/' \
                        | sed -E "s/^'(.*)'\$/\\1/" \
                        | grep -v '^$' || true)
                    while IFS= read -r allowed; do
                        [ -z "$allowed" ] && continue
                        if [[ "$FILE_PATH" == "${allowed}" ]] \
                            || [[ "$FILE_PATH" == "$CWD/${allowed}" ]]; then
                            exit 0
                        fi
                    done <<< "$ALLOWED_PATHS"
                fi
            fi
            echo "VibeGoGo Step ${STEP} (${PHASE}) [${FON_ID}]: ファイル編集は禁止（${PHASE} は .fop-target の VERSION_FILE_*_PATH と progress.md のみ許可、コードのロジック変更は新サイクルで Step 6 implementing で実施）" >&2
            exit 2
        fi
        # branch-pr ワークフロー: commit phase で base ブランチへの直接 commit/push を物理ブロック
        if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "commit" ]; then
            # set -euo pipefail 下でも落ちないよう、各抽出は || true でフェイルセーフにする
            WF=branch-pr; BB=""
            if [ -f "$CWD/.fop-target" ]; then
                WF=$( { grep -E '^WORKFLOW=' "$CWD/.fop-target" 2>/dev/null || true; } | tail -1 | sed -E 's/^[^=]*=//; s/^"//; s/"$//')
                BB=$( { grep -E '^BASE_BRANCH=' "$CWD/.fop-target" 2>/dev/null || true; } | tail -1 | sed -E 's/^[^=]*=//; s/^"//; s/"$//')
                WF=${WF:-branch-pr}
            fi
            if [ "$WF" != "trunk" ]; then
                if [ -z "$BB" ]; then
                    BB=$(git -C "$CWD" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
                    BB=${BB#origin/}
                    BB=${BB:-main}
                fi
                CURBR=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
                # BB はブランチ名（.  +  {  }  (  )  | 等 ERE メタ文字を正当に含みうる）。
                # grep -E に生で埋めると誤判定するため、英数字以外を全エスケープして
                # リテラル一致を保証する。
                BB_RE=$(printf '%s' "$BB" | sed 's/[^[:alnum:]]/\\&/g')
                if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+(commit|push)([[:space:]]|$)'; then
                    if [ "$CURBR" = "$BB" ]; then
                        echo "VibeGoGo Step ${STEP} (commit) [${FON_ID}]: branch-pr では base ブランチ（${BB}）への直接 commit/push は禁止。vibegogo/{id} feature ブランチ上で作業し PR を作成してください（trunk 運用なら .fop-target に WORKFLOW=trunk を明示）" >&2
                        exit 2
                    fi
                    if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+push' \
                        && echo "$COMMAND" | grep -qE "(^|[^a-zA-Z0-9_/.-])${BB_RE}([^a-zA-Z0-9_/.-]|\$)"; then
                        echo "VibeGoGo Step ${STEP} (commit) [${FON_ID}]: branch-pr では base ブランチ（${BB}）への直接 push は禁止。feature ブランチを push して PR 経由でマージしてください" >&2
                        exit 2
                    fi
                fi
            fi
        fi
        ;;
esac

exit 0
