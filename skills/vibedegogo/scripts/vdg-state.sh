#!/bin/bash
# VibeDeGoGo hook/state logic.
#
# state file: .claude/.vdg-state-{id}
# VibeDeGoGo hook/state logic.
# tasks dir:   tasks/vdg/{id}/

# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.
: "${VDG_CWD:=$(pwd)}"

VDG_STATE_DIR="${VDG_STATE_DIR:-${VDG_CWD}/.claude}"
VDG_TASKS_DIR="${VDG_TASKS_DIR:-${VDG_CWD}/tasks/vdg}"

# VibeDeGoGo hook/state logic.

_vdg_generate_id() {
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M)
    local random
    # Avoid SIGPIPE from `tr | head` under caller shells using `set -o pipefail`.
    random=$(LC_ALL=C od -An -N8 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-4)
    echo "${timestamp}-${random}"
}

_vdg_active_file() {
    echo "${VDG_STATE_DIR}/.vdg-active"
}

_vdg_state_file_for_id() {
    local id="$1"
    echo "${VDG_STATE_DIR}/.vdg-state-${id}"
}

# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.
_vdg_rm_glob() {
    [ -d "$1" ] || return 0
    find "$1" -maxdepth 1 -name "$2" -type f -exec rm -f {} + 2>/dev/null || true
}

_vdg_get_active_id() {
    local active_file
    active_file=$(_vdg_active_file)
    if [ -f "$active_file" ]; then
        cat "$active_file"
    else
        echo ""
    fi
}

_vdg_get_state_file() {
    local id
    id=$(_vdg_get_active_id)
    if [ -z "$id" ]; then
        echo ""
        return 1
    fi
    _vdg_state_file_for_id "$id"
}

# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.
_vdg_check_step_transition() {
    local current="$1"
    local next="$2"

    if ! [[ "$next" =~ ^[0-9]+$ ]] || ! [[ "$current" =~ ^[0-9]+$ ]]; then
        echo "vdg-state: invalid or blocked state transition" >&2
        return 1
    fi

    if [ "$next" -eq "$current" ] || [ "$next" -eq $((current + 1)) ]; then
        return 0
    fi
    # VibeDeGoGo hook/state logic.
    if [ "$current" -eq 8 ] && [ "$next" -eq 5 ]; then
        return 0
    fi
    # VibeDeGoGo hook/state logic.
    if [ "$current" -eq 7 ] && [ "$next" -eq 6 ]; then
        return 0
    fi

    echo "vdg-state: invalid or blocked state transition" >&2
    return 1
}

# VibeDeGoGo hook/state logic.

vdg_state_init() {
    local id
    id=$(_vdg_generate_id)
    local active_file
    active_file=$(_vdg_active_file)
    local state_file
    state_file=$(_vdg_state_file_for_id "$id")
    local tasks_dir="${VDG_TASKS_DIR}/${id}"

    # VibeDeGoGo hook/state logic.
    if [ -f "$active_file" ]; then
        local old_id
        old_id=$(cat "$active_file")
        echo "vdg-state: invalid or blocked state transition" >&2
    fi

    mkdir -p "$(dirname "$state_file")"
    mkdir -p "$tasks_dir"

    # VibeDeGoGo hook/state logic.
    _vdg_rm_glob "${VDG_STATE_DIR}" '.vdg-step-block-*'
    rm -f "${VDG_STATE_DIR}/.vdg-error-pending" 2>/dev/null || true
    _vdg_rm_glob "${VDG_STATE_DIR}" '.vdg-simplify-sentinel-*'

    # VibeDeGoGo hook/state logic.
    echo "$id" > "$active_file"

    # VibeDeGoGo hook/state logic.
    cat > "$state_file" << EOF
step=1
phase=declare
loop_count=0
current_task=
vdg_id=${id}
last_updated=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    echo "vdg-state: initialized id=${id}, state=${state_file}, tasks=${tasks_dir}" >&2
}

vdg_state_read() {
    local state_file
    state_file=$(_vdg_get_state_file)
    if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
        echo "step=0"
        echo "phase=none"
        echo "loop_count=0"
        echo "current_task="
        echo "vdg_id="
        echo "last_updated="
        return 1
    fi
    cat "$state_file"
}

vdg_state_write() {
    local new_step="$1"
    local new_phase="$2"
    local new_loop_count="$3"
    local new_current_task="${4:-}"

    if [ -z "$new_step" ] || [ -z "$new_phase" ] || [ -z "$new_loop_count" ]; then
        echo "vdg-state: invalid or blocked state transition" >&2
        return 1
    fi

    if ! [[ "$new_step" =~ ^[0-9]+$ ]]; then
        echo "vdg-state: invalid or blocked state transition" >&2
        return 1
    fi
    if ! [[ "$new_phase" =~ ^[a-z][a-z0-9-]*$ ]]; then
        echo "vdg-state: invalid or blocked state transition" >&2
        return 1
    fi
    if ! [[ "$new_loop_count" =~ ^[0-9]+$ ]]; then
        echo "vdg-state: invalid or blocked state transition" >&2
        return 1
    fi

    local state_file
    state_file=$(_vdg_get_state_file)
    if [ -z "$state_file" ]; then
        echo "vdg-state: invalid or blocked state transition" >&2
        return 1
    fi

    if [ -f "$state_file" ]; then
        local current_step
        current_step=$(grep "^step=" "$state_file" | cut -d= -f2)
        current_step="${current_step:-0}"
        if ! _vdg_check_step_transition "$current_step" "$new_step"; then
            return 1
        fi
    fi

    local id
    id=$(_vdg_get_active_id)

    # VibeDeGoGo hook/state logic.
    if [ -z "$new_current_task" ] && [ -f "$state_file" ]; then
        new_current_task=$(grep "^current_task=" "$state_file" | cut -d= -f2-)
    fi

    cat > "$state_file" << EOF
step=${new_step}
phase=${new_phase}
loop_count=${new_loop_count}
current_task=${new_current_task}
vdg_id=${id}
last_updated=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    echo "vdg-state: -> step=$new_step, phase=$new_phase, loop=$new_loop_count (id=$id)" >&2
}

vdg_state_advance() {
    local next_step="$1"
    local next_phase="$2"

    local state_file
    state_file=$(_vdg_get_state_file)
    if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
        echo "vdg_state_advance: state file not found" >&2
        return 1
    fi

    local current_step
    current_step=$(grep "^step=" "$state_file" | cut -d= -f2)
    current_step="${current_step:-0}"

    # VibeDeGoGo hook/state logic.
    if ! _vdg_check_step_transition "$current_step" "$next_step"; then
        return 1
    fi

    local current_loop
    current_loop=$(grep "^loop_count=" "$state_file" | cut -d= -f2)
    current_loop="${current_loop:-0}"

    local current_task
    current_task=$(grep "^current_task=" "$state_file" | cut -d= -f2-)

    # VibeDeGoGo hook/state logic.
    # VibeDeGoGo hook/state logic.
    # VibeDeGoGo hook/state logic.
    if [ "$current_step" -eq 8 ] && [ "$next_step" -eq 5 ]; then
        current_loop=0
    fi

    vdg_state_write "$next_step" "$next_phase" "$current_loop" "$current_task"
}

vdg_state_loop() {
    local loop_step="$1"
    local loop_phase="$2"

    local state_file
    state_file=$(_vdg_get_state_file)
    if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
        echo "vdg_state_loop: state file not found" >&2
        return 1
    fi

    local current_step
    current_step=$(grep "^step=" "$state_file" | cut -d= -f2)
    current_step="${current_step:-0}"

    # VibeDeGoGo hook/state logic.
    if ! _vdg_check_step_transition "$current_step" "$loop_step"; then
        return 1
    fi

    local current_loop
    current_loop=$(grep "^loop_count=" "$state_file" | cut -d= -f2)
    current_loop="${current_loop:-0}"
    local new_loop=$((current_loop + 1))

    local current_task
    current_task=$(grep "^current_task=" "$state_file" | cut -d= -f2-)

    # VibeDeGoGo hook/state logic.
    # VibeDeGoGo hook/state logic.
    local vdg_id
    vdg_id=$(_vdg_get_active_id)
    if [ -n "$vdg_id" ]; then
        rm -f "${VDG_STATE_DIR}/.vdg-simplify-sentinel-${vdg_id}-${current_loop}" 2>/dev/null || true
    fi

    vdg_state_write "$loop_step" "$loop_phase" "$new_loop" "$current_task"
}

vdg_state_clear() {
    local active_file
    active_file=$(_vdg_active_file)
    local id
    id=$(_vdg_get_active_id)

    if [ -n "$id" ]; then
        local state_file
        state_file=$(_vdg_state_file_for_id "$id")
        if [ -f "$state_file" ]; then
            rm "$state_file"
        fi
    fi

    if [ -f "$active_file" ]; then
        rm "$active_file"
    fi

    # VibeDeGoGo hook/state logic.
    _vdg_rm_glob "${VDG_STATE_DIR}" '.vdg-step-block-*'
    rm -f "${VDG_STATE_DIR}/.vdg-error-pending" 2>/dev/null || true
    _vdg_rm_glob "${VDG_STATE_DIR}" '.vdg-simplify-sentinel-*'

    echo "vdg-state: cleared (id=$id)" >&2
}

# VibeDeGoGo hook/state logic.

vdg_get_tasks_dir() {
    local id
    id=$(_vdg_get_active_id)
    if [ -z "$id" ]; then
        echo "${VDG_CWD}/tasks/vdg"
        return 1
    fi
    echo "${VDG_TASKS_DIR}/${id}"
}

vdg_get_id() {
    _vdg_get_active_id
}
