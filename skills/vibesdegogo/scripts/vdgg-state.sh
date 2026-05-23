#!/bin/bash
# VibesDeGoGo hook/state logic.
#
# state file: .claude/.vdgg-state-{id}
# VibesDeGoGo hook/state logic.
# tasks dir:   tasks/vdgg/{id}/

# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
: "${VDGG_CWD:=$(pwd)}"

VDGG_STATE_DIR="${VDGG_STATE_DIR:-${VDGG_CWD}/.claude}"
VDGG_TASKS_DIR="${VDGG_TASKS_DIR:-${VDGG_CWD}/tasks/vdgg}"

# VibesDeGoGo hook/state logic.

_vdgg_generate_id() {
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M)
    local random
    # Avoid SIGPIPE from `tr | head` under caller shells using `set -o pipefail`.
    random=$(LC_ALL=C od -An -N8 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-4)
    echo "${timestamp}-${random}"
}

_vdgg_active_file() {
    echo "${VDGG_STATE_DIR}/.vdgg-active"
}

_vdgg_state_file_for_id() {
    local id="$1"
    echo "${VDGG_STATE_DIR}/.vdgg-state-${id}"
}

# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
_vdgg_rm_glob() {
    [ -d "$1" ] || return 0
    find "$1" -maxdepth 1 -name "$2" -type f -exec rm -f {} + 2>/dev/null || true
}

_vdgg_get_active_id() {
    local active_file
    active_file=$(_vdgg_active_file)
    if [ -f "$active_file" ]; then
        cat "$active_file"
    else
        echo ""
    fi
}

_vdgg_get_state_file() {
    local id
    id=$(_vdgg_get_active_id)
    if [ -z "$id" ]; then
        echo ""
        return 1
    fi
    _vdgg_state_file_for_id "$id"
}

# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
_vdgg_check_step_transition() {
    local current="$1"
    local next="$2"

    if ! [[ "$next" =~ ^[0-9]+$ ]] || ! [[ "$current" =~ ^[0-9]+$ ]]; then
        echo "vdgg-state: invalid or blocked state transition" >&2
        return 1
    fi

    if [ "$next" -eq "$current" ] || [ "$next" -eq $((current + 1)) ]; then
        return 0
    fi
    # VibesDeGoGo hook/state logic.
    if [ "$current" -eq 8 ] && [ "$next" -eq 5 ]; then
        return 0
    fi
    # VibesDeGoGo hook/state logic.
    if [ "$current" -eq 7 ] && [ "$next" -eq 6 ]; then
        return 0
    fi

    echo "vdgg-state: invalid or blocked state transition" >&2
    return 1
}

# VibesDeGoGo hook/state logic.

vdgg_state_init() {
    local id
    id=$(_vdgg_generate_id)
    local active_file
    active_file=$(_vdgg_active_file)
    local state_file
    state_file=$(_vdgg_state_file_for_id "$id")
    local tasks_dir="${VDGG_TASKS_DIR}/${id}"

    # VibesDeGoGo hook/state logic.
    if [ -f "$active_file" ]; then
        local old_id
        old_id=$(cat "$active_file")
        echo "vdgg-state: invalid or blocked state transition" >&2
    fi

    mkdir -p "$(dirname "$state_file")"
    mkdir -p "$tasks_dir"

    # VibesDeGoGo hook/state logic.
    _vdgg_rm_glob "${VDGG_STATE_DIR}" '.vdgg-step-block-*'
    rm -f "${VDGG_STATE_DIR}/.vdgg-error-pending" 2>/dev/null || true
    _vdgg_rm_glob "${VDGG_STATE_DIR}" '.vdgg-simplify-sentinel-*'

    # VibesDeGoGo hook/state logic.
    echo "$id" > "$active_file"

    # VibesDeGoGo hook/state logic.
    cat > "$state_file" << EOF
step=1
phase=declare
loop_count=0
current_task=
vdgg_id=${id}
last_updated=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    echo "vdgg-state: initialized id=${id}, state=${state_file}, tasks=${tasks_dir}" >&2
}

vdgg_state_read() {
    local state_file
    state_file=$(_vdgg_get_state_file)
    if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
        echo "step=0"
        echo "phase=none"
        echo "loop_count=0"
        echo "current_task="
        echo "vdgg_id="
        echo "last_updated="
        return 1
    fi
    cat "$state_file"
}

vdgg_state_write() {
    local new_step="$1"
    local new_phase="$2"
    local new_loop_count="$3"
    local new_current_task="${4:-}"

    if [ -z "$new_step" ] || [ -z "$new_phase" ] || [ -z "$new_loop_count" ]; then
        echo "vdgg-state: invalid or blocked state transition" >&2
        return 1
    fi

    if ! [[ "$new_step" =~ ^[0-9]+$ ]]; then
        echo "vdgg-state: invalid or blocked state transition" >&2
        return 1
    fi
    if ! [[ "$new_phase" =~ ^[a-z][a-z0-9-]*$ ]]; then
        echo "vdgg-state: invalid or blocked state transition" >&2
        return 1
    fi
    if ! [[ "$new_loop_count" =~ ^[0-9]+$ ]]; then
        echo "vdgg-state: invalid or blocked state transition" >&2
        return 1
    fi

    local state_file
    state_file=$(_vdgg_get_state_file)
    if [ -z "$state_file" ]; then
        echo "vdgg-state: invalid or blocked state transition" >&2
        return 1
    fi

    if [ -f "$state_file" ]; then
        local current_step
        current_step=$(grep "^step=" "$state_file" | cut -d= -f2)
        current_step="${current_step:-0}"
        if ! _vdgg_check_step_transition "$current_step" "$new_step"; then
            return 1
        fi
    fi

    local id
    id=$(_vdgg_get_active_id)

    # VibesDeGoGo hook/state logic.
    if [ -z "$new_current_task" ] && [ -f "$state_file" ]; then
        new_current_task=$(grep "^current_task=" "$state_file" | cut -d= -f2-)
    fi

    cat > "$state_file" << EOF
step=${new_step}
phase=${new_phase}
loop_count=${new_loop_count}
current_task=${new_current_task}
vdgg_id=${id}
last_updated=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    echo "vdgg-state: -> step=$new_step, phase=$new_phase, loop=$new_loop_count (id=$id)" >&2
}

vdgg_state_advance() {
    local next_step="$1"
    local next_phase="$2"

    local state_file
    state_file=$(_vdgg_get_state_file)
    if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
        echo "vdgg_state_advance: state file not found" >&2
        return 1
    fi

    local current_step
    current_step=$(grep "^step=" "$state_file" | cut -d= -f2)
    current_step="${current_step:-0}"

    # VibesDeGoGo hook/state logic.
    if ! _vdgg_check_step_transition "$current_step" "$next_step"; then
        return 1
    fi

    local current_loop
    current_loop=$(grep "^loop_count=" "$state_file" | cut -d= -f2)
    current_loop="${current_loop:-0}"

    local current_task
    current_task=$(grep "^current_task=" "$state_file" | cut -d= -f2-)

    # VibesDeGoGo hook/state logic.
    # VibesDeGoGo hook/state logic.
    # VibesDeGoGo hook/state logic.
    if [ "$current_step" -eq 8 ] && [ "$next_step" -eq 5 ]; then
        current_loop=0
    fi

    vdgg_state_write "$next_step" "$next_phase" "$current_loop" "$current_task"
}

vdgg_state_loop() {
    local loop_step="$1"
    local loop_phase="$2"

    local state_file
    state_file=$(_vdgg_get_state_file)
    if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
        echo "vdgg_state_loop: state file not found" >&2
        return 1
    fi

    local current_step
    current_step=$(grep "^step=" "$state_file" | cut -d= -f2)
    current_step="${current_step:-0}"

    # VibesDeGoGo hook/state logic.
    if ! _vdgg_check_step_transition "$current_step" "$loop_step"; then
        return 1
    fi

    local current_loop
    current_loop=$(grep "^loop_count=" "$state_file" | cut -d= -f2)
    current_loop="${current_loop:-0}"
    local new_loop=$((current_loop + 1))

    local current_task
    current_task=$(grep "^current_task=" "$state_file" | cut -d= -f2-)

    # VibesDeGoGo hook/state logic.
    # VibesDeGoGo hook/state logic.
    local vdgg_id
    vdgg_id=$(_vdgg_get_active_id)
    if [ -n "$vdgg_id" ]; then
        rm -f "${VDGG_STATE_DIR}/.vdgg-simplify-sentinel-${vdgg_id}-${current_loop}" 2>/dev/null || true
    fi

    vdgg_state_write "$loop_step" "$loop_phase" "$new_loop" "$current_task"
}

vdgg_state_clear() {
    local active_file
    active_file=$(_vdgg_active_file)
    local id
    id=$(_vdgg_get_active_id)

    if [ -n "$id" ]; then
        local state_file
        state_file=$(_vdgg_state_file_for_id "$id")
        if [ -f "$state_file" ]; then
            rm "$state_file"
        fi
    fi

    if [ -f "$active_file" ]; then
        rm "$active_file"
    fi

    # VibesDeGoGo hook/state logic.
    _vdgg_rm_glob "${VDGG_STATE_DIR}" '.vdgg-step-block-*'
    rm -f "${VDGG_STATE_DIR}/.vdgg-error-pending" 2>/dev/null || true
    _vdgg_rm_glob "${VDGG_STATE_DIR}" '.vdgg-simplify-sentinel-*'

    echo "vdgg-state: cleared (id=$id)" >&2
}

# VibesDeGoGo hook/state logic.

vdgg_get_tasks_dir() {
    local id
    id=$(_vdgg_get_active_id)
    if [ -z "$id" ]; then
        echo "${VDGG_CWD}/tasks/vdgg"
        return 1
    fi
    echo "${VDGG_TASKS_DIR}/${id}"
}

vdgg_get_id() {
    _vdgg_get_active_id
}
