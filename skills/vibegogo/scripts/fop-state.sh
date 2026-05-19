#!/bin/bash
# fop-state.sh — VibeGoGo state file 操作ヘルパー（ID対応版）
#
# state file: .claude/.fop-state-{id}
# active file: .claude/.fop-active  (現在アクティブなIDを格納)
# tasks dir:   tasks/fop/{id}/

# FON_CWD 決定: 環境変数で明示指定があればそれ、無ければ source 時点の PWD を記録
# （以後 cd されても追従しない）
: "${FON_CWD:=$(pwd)}"

FON_STATE_DIR="${FON_STATE_DIR:-${FON_CWD}/.claude}"
FON_TASKS_DIR="${FON_TASKS_DIR:-${FON_CWD}/tasks/fop}"

# --- 内部ヘルパー ---

_fop_generate_id() {
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M)
    local random
    random=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c4)
    echo "${timestamp}-${random}"
}

_fop_active_file() {
    echo "${FON_STATE_DIR}/.fop-active"
}

_fop_state_file_for_id() {
    local id="$1"
    echo "${FON_STATE_DIR}/.fop-state-${id}"
}

_fop_get_active_id() {
    local active_file
    active_file=$(_fop_active_file)
    if [ -f "$active_file" ]; then
        cat "$active_file"
    else
        echo ""
    fi
}

_fop_get_state_file() {
    local id
    id=$(_fop_get_active_id)
    if [ -z "$id" ]; then
        echo ""
        return 1
    fi
    _fop_state_file_for_id "$id"
}

# Step 連続性チェック
# 許可: +0 / +1 / 8→5 (未完了タスク戻り) / 7→6 (reflection→implementing)
_fop_check_step_transition() {
    local current="$1"
    local next="$2"

    if ! [[ "$next" =~ ^[0-9]+$ ]] || ! [[ "$current" =~ ^[0-9]+$ ]]; then
        echo "fop-state: step は数値である必要があります (current=${current}, next=${next})" >&2
        return 1
    fi

    if [ "$next" -eq "$current" ] || [ "$next" -eq $((current + 1)) ]; then
        return 0
    fi
    # 新体系: progress(8) → task-selected(5) 戻り
    if [ "$current" -eq 8 ] && [ "$next" -eq 5 ]; then
        return 0
    fi
    # 新体系: testing(7) → implementing(6) 往復
    if [ "$current" -eq 7 ] && [ "$next" -eq 6 ]; then
        return 0
    fi

    echo "fop-state: Step 飛ばし/不正遷移禁止 (current=${current} → next=${next})。許可: +0 / +1 / 8→5 / 7→6" >&2
    return 1
}

# --- 公開関数 ---

fop_state_init() {
    local id
    id=$(_fop_generate_id)
    local active_file
    active_file=$(_fop_active_file)
    local state_file
    state_file=$(_fop_state_file_for_id "$id")
    local tasks_dir="${FON_TASKS_DIR}/${id}"

    # active file が既にあれば警告（前回のVibeGoGoが未完了）
    if [ -f "$active_file" ]; then
        local old_id
        old_id=$(cat "$active_file")
        echo "fop-state: 警告 — 前回のVibeGoGo (${old_id}) が未完了です。新しいVibeGoGoを開始します" >&2
    fi

    mkdir -p "$(dirname "$state_file")"
    mkdir -p "$tasks_dir"

    # 中断（clear せず放棄）された前セッションの残骸を掃除し、新セッションへの汚染を防ぐ
    rm -f "${FON_STATE_DIR}"/.fop-step-block-* 2>/dev/null || true
    rm -f "${FON_STATE_DIR}/.fop-error-pending" 2>/dev/null || true
    rm -f "${FON_STATE_DIR}"/.fop-simplify-sentinel-* 2>/dev/null || true

    # active file にIDを書き込み
    echo "$id" > "$active_file"

    # state file を初期化
    cat > "$state_file" << EOF
step=1
phase=declare
loop_count=0
current_task=
fop_id=${id}
last_updated=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    echo "fop-state: initialized id=${id}, state=${state_file}, tasks=${tasks_dir}" >&2
}

fop_state_read() {
    local state_file
    state_file=$(_fop_get_state_file)
    if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
        echo "step=0"
        echo "phase=none"
        echo "loop_count=0"
        echo "current_task="
        echo "fop_id="
        echo "last_updated="
        return 1
    fi
    cat "$state_file"
}

fop_state_write() {
    local new_step="$1"
    local new_phase="$2"
    local new_loop_count="$3"
    local new_current_task="${4:-}"

    if [ -z "$new_step" ] || [ -z "$new_phase" ] || [ -z "$new_loop_count" ]; then
        echo "fop_state_write: 引数エラー" >&2
        return 1
    fi

    if ! [[ "$new_step" =~ ^[0-9]+$ ]]; then
        echo "fop_state_write: step は数値: $new_step" >&2
        return 1
    fi
    if ! [[ "$new_phase" =~ ^[a-z][a-z0-9-]*$ ]]; then
        echo "fop_state_write: phase は英小文字とハイフン: $new_phase" >&2
        return 1
    fi
    if ! [[ "$new_loop_count" =~ ^[0-9]+$ ]]; then
        echo "fop_state_write: loop_count は数値: $new_loop_count" >&2
        return 1
    fi

    local state_file
    state_file=$(_fop_get_state_file)
    if [ -z "$state_file" ]; then
        echo "fop_state_write: active なVibeGoGoがありません" >&2
        return 1
    fi

    local id
    id=$(_fop_get_active_id)

    # current_task: 引数省略時は既存 state file から引き継ぎ
    if [ -z "$new_current_task" ] && [ -f "$state_file" ]; then
        new_current_task=$(grep "^current_task=" "$state_file" | cut -d= -f2-)
    fi

    cat > "$state_file" << EOF
step=${new_step}
phase=${new_phase}
loop_count=${new_loop_count}
current_task=${new_current_task}
fop_id=${id}
last_updated=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    echo "fop-state: -> step=$new_step, phase=$new_phase, loop=$new_loop_count (id=$id)" >&2
}

fop_state_advance() {
    local next_step="$1"
    local next_phase="$2"

    local state_file
    state_file=$(_fop_get_state_file)
    if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
        echo "fop_state_advance: state file not found" >&2
        return 1
    fi

    local current_step
    current_step=$(grep "^step=" "$state_file" | cut -d= -f2)
    current_step="${current_step:-0}"

    # Step 連続性チェック（ガード1）
    if ! _fop_check_step_transition "$current_step" "$next_step"; then
        return 1
    fi

    local current_loop
    current_loop=$(grep "^loop_count=" "$state_file" | cut -d= -f2)
    current_loop="${current_loop:-0}"

    local current_task
    current_task=$(grep "^current_task=" "$state_file" | cut -d= -f2-)

    # 8→5（progress → task-selected = 次タスク着手）では loop_count を 0 にリセット。
    # loop_count は「同タスクの試行回数」であり、タスクを跨いで累積させると
    # アーキ検討必須（>3）/ 上限（99）判定が誤発火する。
    if [ "$current_step" -eq 8 ] && [ "$next_step" -eq 5 ]; then
        current_loop=0
    fi

    fop_state_write "$next_step" "$next_phase" "$current_loop" "$current_task"
}

fop_state_loop() {
    local loop_step="$1"
    local loop_phase="$2"

    local state_file
    state_file=$(_fop_get_state_file)
    if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
        echo "fop_state_loop: state file not found" >&2
        return 1
    fi

    local current_step
    current_step=$(grep "^step=" "$state_file" | cut -d= -f2)
    current_step="${current_step:-0}"

    # Step 連続性チェック（ガード1）
    if ! _fop_check_step_transition "$current_step" "$loop_step"; then
        return 1
    fi

    local current_loop
    current_loop=$(grep "^loop_count=" "$state_file" | cut -d= -f2)
    current_loop="${current_loop:-0}"
    local new_loop=$((current_loop + 1))

    local current_task
    current_task=$(grep "^current_task=" "$state_file" | cut -d= -f2-)

    # ループ遷移時、旧 loop_count に対応する simplify sentinel を削除
    # （次サイクルへの持ち越しを防止。新 loop_count の sentinel は必要時に新規作成される）
    local fop_id
    fop_id=$(_fop_get_active_id)
    if [ -n "$fop_id" ]; then
        rm -f "${FON_STATE_DIR}/.fop-simplify-sentinel-${fop_id}-${current_loop}" 2>/dev/null || true
    fi

    fop_state_write "$loop_step" "$loop_phase" "$new_loop" "$current_task"
}

fop_state_clear() {
    local active_file
    active_file=$(_fop_active_file)
    local id
    id=$(_fop_get_active_id)

    if [ -n "$id" ]; then
        local state_file
        state_file=$(_fop_state_file_for_id "$id")
        if [ -f "$state_file" ]; then
            rm "$state_file"
        fi
    fi

    if [ -f "$active_file" ]; then
        rm "$active_file"
    fi

    # 同 turn retry block フラグの残骸を一掃（次セッション汚染防止）
    rm -f "${FON_STATE_DIR}"/.fop-step-block-* 2>/dev/null || true
    rm -f "${FON_STATE_DIR}/.fop-error-pending" 2>/dev/null || true
    rm -f "${FON_STATE_DIR}"/.fop-simplify-sentinel-* 2>/dev/null || true

    echo "fop-state: cleared (id=$id)" >&2
}

# --- ユーティリティ ---

fop_get_tasks_dir() {
    local id
    id=$(_fop_get_active_id)
    if [ -z "$id" ]; then
        echo "${FON_CWD}/tasks/fop"
        return 1
    fi
    echo "${FON_TASKS_DIR}/${id}"
}

fop_get_id() {
    _fop_get_active_id
}
