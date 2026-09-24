#!/bin/bash
set -euo pipefail

# `git commit` を単語として捉えるパターン。commit guard の 3 箇所が
# 同じ判定を共有するため、ここ 1 箇所で定義する。
GIT_COMMIT_PATTERN='(^|[^a-zA-Z0-9_-])git[[:space:]]+commit($|[[:space:]])'

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  # Keep jq install-command detection and guidance aligned across the Claude
  # pretool/posttool and Codex pretool hooks. Their activation checks differ;
  # Codex posttool intentionally exits 0 without jq and has no install guidance.
  # Best-effort cwd extraction without jq: parse the "cwd" field with grep/sed.
  FALLBACK_CWD=$(printf '%s' "$INPUT" | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/')
  FALLBACK_CWD="${FALLBACK_CWD:-$PWD}"
  # Resolve to the git toplevel the same way the jq path does.
  if R=$(git -C "$FALLBACK_CWD" rev-parse --show-toplevel 2>/dev/null); then
    FALLBACK_CWD="$R"
  fi
  # Fail-open when inactive: no active session means nothing to protect, so stay
  # out of the way rather than blocking every tool in unrelated repositories.
  # Exception: when the repository opts in with VDGG_REQUIRED=on, tools cannot
  # be classified without jq, so fall through to the fail-closed branch below.
  if [ ! -f "$FALLBACK_CWD/.codex/.vdgg-active" ]; then
    FALLBACK_REQUIRED=$(grep -m1 '^VDGG_REQUIRED=' "$FALLBACK_CWD/.vdgg-target" 2>/dev/null | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/' || true)
    if [ "$FALLBACK_REQUIRED" != "on" ]; then
      exit 0
    fi
  fi
  # Active session: cannot parse JSON properly, so fail closed. Allow jq-install
  # commands through so the user can fix the missing dependency.
  if printf '%s' "$INPUT" | grep -qE '"command"[[:space:]]*:[[:space:]]*"[^"]*(brew[[:space:]]+(install|reinstall)|apt(-get)?[[:space:]]+install|apk[[:space:]]+add|dnf[[:space:]]+install|yum[[:space:]]+install|pacman[[:space:]]+-S)[[:space:]]+[^"]*jq'; then
    exit 0
  fi
  {
    echo "VibesDeGoGo! for Codex: jq is required for hooks but was not found on PATH."
    echo "  macOS:               brew install jq"
    echo "  Debian/Ubuntu/WSL:   sudo apt-get install jq"
    echo "  Alpine:              apk add jq"
    echo "  Fedora/RHEL:         sudo dnf install jq"
  } >&2
  exit 2
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$CWD" ] || CWD=$(pwd)
if ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null); then
  CWD="$ROOT"
fi

# Entry gate (VDGG_REQUIRED): normally an unarmed session (no active id or
# state) leaves the hook fail-open so unrelated repositories are never
# touched. A repository can opt out of that leniency with VDGG_REQUIRED=on in
# .vdgg-target: code-modifying tools are then denied until a session is armed
# through vdgg_state_init. This closes the hole where an agent that ignores
# the workflow contract simply never arms the gates (arming must not be a
# voluntary act). Only the literal value `on` activates the gate. Gated tools
# match the armed path (apply_patch/Edit/Write/Bash); other tools pass, as
# they do when armed. Known limit (same as the sidecar guard): a write hidden
# behind a shell variable or an interpreter one-liner evades the literal
# segment match.
_vdgg_required() {
  local target="$CWD/.vdgg-target" v
  [ -f "$target" ] || return 1
  v=$(grep -m1 '^VDGG_REQUIRED=' "$target" | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/' || true)
  [ "$v" = "on" ]
}

_vdgg_entry_deny() {
  echo "VibesDeGoGo! for Codex entry gate: this repository sets VDGG_REQUIRED=on in .vdgg-target and no VibesDeGoGo! session is armed. Code-modifying tools are blocked until Step 1 runs: source the skill's scripts/vdgg-state.sh and run vdgg_state_init. Only a human may relax this by editing .vdgg-target." >&2
  exit 2
}

_vdgg_entry_gate() {
  local tool cmd segs seg seg_checked verb
  tool=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
  case "$tool" in
    apply_patch|Edit|Write)
      _vdgg_entry_deny
      ;;
    Bash)
      cmd=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
      segs="$cmd"
      segs="${segs//&&/$'\n'}"
      segs="${segs//||/$'\n'}"
      segs="${segs//;/$'\n'}"
      segs="${segs//|/$'\n'}"
      while IFS= read -r seg; do
        # Redirections to /dev/null|stdout|stderr do not modify the
        # repository; strip them (fd dups like 2>&1 are already excluded by
        # the [^&] below) so read-only idioms are not falsely denied.
        seg_checked=$(printf '%s' "$seg" | sed -E 's#[0-9]*>>?[[:space:]]*/dev/(null|stdout|stderr)##g')
        if printf '%s' "$seg_checked" | grep -qE '(>[^&]|>>|(^|[[:space:]])tee([[:space:]]|$))'; then
          _vdgg_entry_deny
        fi
        if printf '%s' "$seg" | grep -qE "$GIT_COMMIT_PATTERN"; then
          _vdgg_entry_deny
        fi
        verb=$(printf '%s' "$seg" | sed -E 's/^[[:space:]]*//; s/[[:space:]].*//')
        case "$verb" in
          rm|mv|cp|dd|install|truncate|touch|ln|patch|mkfifo|apply_patch)
            # apply_patch also arrives as a shell command in some Codex
            # versions, not only as the apply_patch tool.
            _vdgg_entry_deny
            ;;
          sed|perl)
            if printf '%s' "$seg" | grep -qE '(^|[[:space:]])-[a-zA-Z]*i'; then
              _vdgg_entry_deny
            fi
            ;;
        esac
      done <<< "$segs"
      exit 0
      ;;
    *)
      exit 0
      ;;
  esac
}

# Unarmed exit: with the VDGG_REQUIRED opt-in the entry gate decides
# (always exits); without it the hook stays out of the way.
_vdgg_unarmed_exit() {
  if _vdgg_required; then
    _vdgg_entry_gate
  fi
  exit 0
}

ACTIVE_FILE="$CWD/.codex/.vdgg-active"
[ -f "$ACTIVE_FILE" ] || _vdgg_unarmed_exit
VDGG_ID=$(cat "$ACTIVE_FILE")
[ -n "$VDGG_ID" ] || _vdgg_unarmed_exit
STATE_FILE="$CWD/.codex/.vdgg-state-${VDGG_ID}"
[ -f "$STATE_FILE" ] || _vdgg_unarmed_exit

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
# Transition gates match `vdgg_state_* <step> <phase>` literally; quoting an
# argument ("4" planning) must not step around them. apply_patch bodies keep
# COMMAND as is, so only the gate copy is unquoted.
GATE_COMMAND=$(printf '%s' "$COMMAND" | tr -d "\"'")
# 状態ファイルから 1 フィールドを読む。値に `=` を含みうるので常に f2- を使う。
_vdgg_state_get() {
  grep "^$1=" "$2" | head -1 | cut -d= -f2- || true
}

PHASE=$(_vdgg_state_get phase "$STATE_FILE")
STEP=$(_vdgg_state_get step "$STATE_FILE")
LOOP_COUNT=$(_vdgg_state_get loop_count "$STATE_FILE")
LOOP_COUNT="${LOOP_COUNT:-0}"
TASK_ALLOWLIST_FILE=$(_vdgg_state_get task_allowlist_file "$STATE_FILE")
TASK_GATE_FILE="$CWD/.codex/.vdgg-task-gate-${VDGG_ID}-${LOOP_COUNT}"
TASKS_DIR="$CWD/tasks/vdgg/${VDGG_ID}"

block() {
  echo "VibesDeGoGo! for Codex [${VDGG_ID}]: $1" >&2
  exit 2
}

# Evidence gates shared with the Claude Code edition (vdgg-evidence.sh, kept
# byte-identical): the Step 3 read log, the Step 4 plan excerpts, the Step 6
# patch chain and the Step 7 plan reconciliation.
_VDGG_CX_HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
# A partial install must not quietly open the gates.
[ -f "${_VDGG_CX_HOOK_DIR}/vdgg-evidence.sh" ] || block "vdgg-evidence.sh is missing next to the hook; reinstall the skill."
# shellcheck source=vdgg-evidence.sh
. "${_VDGG_CX_HOOK_DIR}/vdgg-evidence.sh"
READ_LOG="$CWD/.codex/.vdgg-read-${VDGG_ID}"

# A transition whose step/phase is not literal (a variable, $'...', a
# backslash) cannot be judged against the gates, so it is refused.
if [ "$TOOL_NAME" = "Bash" ] && ! _vdgg_ev_transitions_literal "$COMMAND"; then
  block "write vdgg_state_advance/loop/write with a literal step and phase (e.g. vdgg_state_advance 4 planning); variables, escapes and \$'...' cannot be checked against the gates."
fi

# Portable mtime in epoch seconds. BSD/macOS `stat -f %m` gives the epoch. On
# GNU/Linux `-f` means --file-system and prints non-numeric text with exit 0, so
# the raw `||` chain is not enough: validate the result is all-digits and fall
# back to `stat -c %Y`, then to 0.
_vdgg_mtime() {
  local m
  m=$(stat -f %m "$1" 2>/dev/null || true)
  case "$m" in ''|*[!0-9]*) m=$(stat -c %Y "$1" 2>/dev/null || true) ;; esac
  case "$m" in ''|*[!0-9]*) m=0 ;; esac
  printf '%s\n' "$m"
}

patch_files() {
  printf '%s\n' "$COMMAND" \
    | sed -nE 's/^\*\*\* (Add|Update|Delete) File: (.*)$/\2/p'
}

changed_files() {
  case "$TOOL_NAME" in
    apply_patch)
      patch_files
      ;;
    Edit|Write)
      printf '%s\n' "$INPUT" | jq -r '.tool_input.file_path // empty'
      ;;
  esac
}

normalize_project_path() {
  local p="$1"
  case "$p" in
    "$CWD"/*) p="${p#"$CWD"/}" ;;
    ./*) p="${p#./}" ;;
  esac
  printf '%s\n' "$p"
}

path_is_tasks_file() {
  # A tool may hand us an absolute path, a bare relative one, or a ./-prefixed
  # one; normalize before matching so all three forms are treated alike. The
  # raw comparison silently missed the ./ form.
  local p="${1#./}"
  p="${p#"$CWD"/}"
  [[ "$p" == "tasks/vdgg/${VDGG_ID}/"* ]]
}

path_is_task_allowlisted() {
  local p
  p=$(normalize_project_path "$1")
  [ -n "${TASK_ALLOWLIST_FILE:-}" ] || return 1
  [ -f "$TASK_ALLOWLIST_FILE" ] || return 1
  grep -qxF "$p" "$TASK_ALLOWLIST_FILE"
}

path_is_sidecar_file() {
  local p="$1"
  [[ "$p" == *".codex/.vdgg-"* ]] || [[ "$p" == *".vdgg-target" ]]
}

if [ "$TOOL_NAME" = "Bash" ] && [ -f "$CWD/.codex/.vdgg-error-pending" ]; then
  if ! printf '%s' "$COMMAND" | grep -qF '[Error Acknowledged]'; then
    block "Previous command failed. Acknowledge it with [Error Acknowledged] before running another command."
  fi
  rm -f "$CWD/.codex/.vdgg-error-pending"
fi

if [ "$TOOL_NAME" = "Bash" ]; then
  # Sidecar files (.codex/.vdgg-*) may only be written through vdgg_state_*
  # helpers, and .vdgg-target only by a human (it holds executed config:
  # REVIEW_COMMAND). Split the command into shell
  # segments so a `git commit` segment (whose message may mention such a path)
  # cannot shield a mutating segment in the same line, e.g.
  #   git commit -m x && rm -f .codex/.vdgg-active
  # Whitelist model (fail-closed): a segment mentioning a protected path is
  # allowed only when it is a git-commit segment or a genuine read (leading
  # read-only verb, no output redirection / tee). Everything else (python/perl,
  # dd/install, redirects, file ops) is denied. Known limit: a path hidden
  # behind a shell variable or command substitution evades the literal match.
  _vdgg_segs="$COMMAND"
  _vdgg_segs="${_vdgg_segs//&&/$'\n'}"
  _vdgg_segs="${_vdgg_segs//||/$'\n'}"
  _vdgg_segs="${_vdgg_segs//;/$'\n'}"
  _vdgg_segs="${_vdgg_segs//|/$'\n'}"
  while IFS= read -r _vdgg_seg; do
    case "$_vdgg_seg" in
      *".codex/.vdgg-"*|*".vdgg-target"*) ;;
      *) continue ;;
    esac
    if printf '%s' "$_vdgg_seg" | grep -qE "$GIT_COMMIT_PATTERN"; then
      continue
    fi
    _vdgg_verb=$(printf '%s' "$_vdgg_seg" | sed -E 's/^[[:space:]]*//; s/[[:space:]].*//')
    _vdgg_read_ok=0
    case "$_vdgg_verb" in
      cat|grep|egrep|fgrep|test|'['|ls|head|tail|wc|diff|cmp|stat|od|hexdump|file|realpath|readlink)
        # Strip `2>/dev/null` before the redirect test: silencing stderr is
        # not a write, and a segment that also writes keeps its `>`.
        # SECURITY: /dev/null ONLY -- never widen to the entry gate's
        # /dev/stdout|stderr. This pattern has no terminator, so
        # `>/dev/stdout/<path>` would be swallowed whole, and fd 1 can be
        # aimed into the repo with `1<.`. /dev/null is a character device,
        # so `/dev/null/<x>` is always ENOTDIR.
        # See skills/vibesdegogo/references/hook_rules.md.
        _vdgg_seg_checked=$(printf '%s' "$_vdgg_seg" | sed -E 's#[0-9]*>>?[[:space:]]*/dev/null##g')
        if ! printf '%s' "$_vdgg_seg_checked" | grep -qE '(>[^&]|>>|(^|[[:space:]])tee([[:space:]]|$))'; then
          _vdgg_read_ok=1
        fi
        ;;
    esac
    [ "$_vdgg_read_ok" -eq 1 ] || block "Direct writes to VibesDeGoGo! sidecar/target files are blocked. Use vdgg_state_* helpers; .vdgg-target must be set by a human. To read one, lead with a read-only verb such as cat/grep/head and add no output redirection (only /dev/null is exempt)."
  done <<< "$_vdgg_segs"
fi

if [ "$TOOL_NAME" = "apply_patch" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
  while IFS= read -r file_path; do
    [ -n "$file_path" ] || continue
    path_is_sidecar_file "$file_path" && block "Direct edits to VibesDeGoGo! sidecar files are blocked. Use vdgg_state_* helpers."
  done < <(changed_files)
fi

if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "requirements" ]; then
  if printf '%s' "$GATE_COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+3[[:space:]]+investigating'; then
    [ -f "$TASKS_DIR/requirements.md" ] || block "requirements.md is required before investigation."
    # The '## Lessons Applied' heading with a non-empty body is enforced at the
    # earliest structural point where user-memory / AIB lessons still shape the
    # requirements themselves, so the consultation can never be silently skipped.
    awk '
      /^## Lessons Applied[[:space:]]*$/ { in_section=1; next }
      in_section && /^## / { in_section=0 }
      in_section && /[^[:space:]]/ { found=1 }
      END { exit found ? 0 : 1 }
    ' "$TASKS_DIR/requirements.md" \
      || block "requirements.md must include a '## Lessons Applied' heading with a non-empty body (write 'None applicable' when nothing fits)."
  fi
fi

if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "investigating" ]; then
  if printf '%s' "$GATE_COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+4[[:space:]]+planning'; then
    [ -f "$TASKS_DIR/investigation.md" ] || block "investigation.md is required before planning."
    # Seven direct pattern-action blocks mirror the Step 2->3 gate style above.
    # Adding or renaming a heading requires editing this block and SKILL.md's
    # Step 3 list together (this Codex edition has no references/subagent_prompts.md;
    # the Claude edition's copy of that file is a third source pinned by the
    # cross-edition drift test in tests/).
    awk '
      BEGIN { current = 0 }
      /^## 1\. Related files[[:space:]]*$/                { seen[1]=1; current=1; next }
      /^## 2\. Existing implementation patterns[[:space:]]*$/ { seen[2]=1; current=2; next }
      /^## 3\. Impact surface[[:space:]]*$/               { seen[3]=1; current=3; next }
      /^## 4\. Prior similar implementations[[:space:]]*$/ { seen[4]=1; current=4; next }
      /^## 5\. Side effects and risks[[:space:]]*$/       { seen[5]=1; current=5; next }
      /^## 6\. Constraints[[:space:]]*$/                  { seen[6]=1; current=6; next }
      /^## 7\. Verification strategy[[:space:]]*$/        { seen[7]=1; current=7; next }
      current > 0 && /^## /               { current = 0 }
      current > 0 && /[^[:space:]]/       { body[current] = 1 }
      END { for (i = 1; i <= 7; i++) if (!seen[i] || !body[i]) exit 1 }
    ' "$TASKS_DIR/investigation.md" \
      || block "investigation.md must include all seven required Step 3 headings each with a non-empty body (see SKILL.md Step 3)."
    # Read evidence: every file under '## 1. Related files' must exist and
    # have been read (by a Bash reader) during this phase.
    if ! READ_PROBLEMS=$(_vdgg_ev_check_related "$TASKS_DIR/investigation.md" "$READ_LOG" "$CWD"); then
      block "Step 3 read evidence is missing. Every file listed under '## 1. Related files' must exist and be read during investigating (cat, sed -n, head, rg ...): $(printf '%s' "$READ_PROBLEMS" | tr '\n' ';')"
    fi
  fi
fi

# Plan evidence: leaving Step 4 (vdgg_state_advance 5, or vdgg_task_begin,
# which also writes step 5) needs todo.md tasks whose excerpts match the
# current code verbatim and whose intent carries no code.
if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "planning" ]; then
  if printf '%s' "$GATE_COMMAND" | grep -qE '(vdgg_state_(advance|loop|write)[[:space:]]+5[[:space:]]+task-selected|vdgg_task_begin)([^[:alnum:]_-]|$)'; then
    if ! PLAN_PROBLEMS=$(_vdgg_ev_check_plan "$TASKS_DIR/todo.md" "$CWD"); then
      block "todo.md does not carry plan evidence. Each '## T<n>' task needs '### Location', '### Excerpt' (the current code there, copied verbatim in one fenced block, or 新規 for a new file) and '### Intent' (prose, no code): $(printf '%s' "$PLAN_PROBLEMS" | tr '\n' ';')"
    fi
    [ -f "$TASKS_DIR/progress.md" ] || block "progress.md is required before Step 5."
  fi
fi

if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "implementing" ]; then
  TEST_PATTERN='swift[[:space:]]+test|xcodebuild[[:space:]]+[^|]*[[:space:]]test|pytest|npm[[:space:]]+(run[[:space:]]+)?test|pnpm[[:space:]]+(run[[:space:]]+)?test|yarn[[:space:]]+(run[[:space:]]+)?test|go[[:space:]]+test|cargo[[:space:]]+test|jest|vitest|mocha'
  if [ -f "$CWD/.vdgg-target" ]; then
    EXTRA=$(grep '^TEST_COMMAND_PATTERN=' "$CWD/.vdgg-target" 2>/dev/null | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/' | head -1)
    [ -z "${EXTRA:-}" ] || TEST_PATTERN="${TEST_PATTERN}|${EXTRA}"
  fi
  if printf '%s' "$COMMAND" | grep -qE "(^|[[:space:];&|(])(${TEST_PATTERN})([[:space:]]|$)"; then
    block "Tests are blocked in implementing. Advance to Step 7 testing first."
  fi
fi

case "$PHASE" in
  declare|requirements|investigating|planning)
    if [ "$TOOL_NAME" = "apply_patch" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
      while IFS= read -r file_path; do
        [ -n "$file_path" ] || continue
        path_is_tasks_file "$file_path" || block "Only the active tasks/vdgg/${VDGG_ID}/ files may be edited in phase ${PHASE}."
      done < <(changed_files)
    fi
    ;;
  task-selected)
    if [ "$TOOL_NAME" = "apply_patch" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
      block "Edits are blocked in task-selected. Advance to implementing first."
    fi
    ;;
  implementing|testing)
    if [ "$TOOL_NAME" = "apply_patch" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
      while IFS= read -r file_path; do
        [ -n "$file_path" ] || continue
        # Task notes under tasks/vdgg/{id}/ stay editable without allowlisting.
        path_is_tasks_file "$file_path" && continue
        # Step 6 is patch first: implementation files change only through
        # vdgg_patch_apply / vdgg_codemod_apply, which the 6 -> 7 gate below
        # checks. Testing refuses direct edits too: a review fix goes through
        # reflection and the next loop's patch.
        block "Review fixes too go through reflection and a patch. Step 6 is patch first: write the change as a unified diff under tasks/vdgg/${VDGG_ID}/patch/ and apply it with vdgg_patch_apply <file> (mechanical bulk edits: vdgg_codemod_apply <expected-files> <command>)."
        [ -n "${TASK_ALLOWLIST_FILE:-}" ] && [ -f "$TASK_ALLOWLIST_FILE" ] \
          || block "No active task allowlist. Run vdgg_task_begin before editing implementation files."
        path_is_task_allowlisted "$file_path" \
          || block "Task allowlist blocks edit: $(normalize_project_path "$file_path")"
      done < <(changed_files)
    fi
    if [ "$TOOL_NAME" = "Bash" ] && printf '%s' "$COMMAND" | grep -qE "$GIT_COMMIT_PATTERN"; then
      block "Commit is blocked before Step 9."
    fi
    # Patch evidence: 6 -> 7 needs at least one vdgg_patch_apply or
    # vdgg_codemod_apply for this task, and the allowlisted files must still
    # hold exactly what the last one left.
    if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "implementing" ] \
      && printf '%s' "$GATE_COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+7[[:space:]]+testing([^[:alnum:]_-]|$)'; then
      if ! CHAIN_PROBLEMS=$(_vdgg_ev_chain_check "$CWD/.codex/.vdgg-task-patchchain-${VDGG_ID}" "${TASK_ALLOWLIST_FILE:-}" "$CWD"); then
        block "Step 6 patch evidence is missing: ${CHAIN_PROBLEMS}. Apply changes with vdgg_patch_apply (or vdgg_codemod_apply); after an out-of-band edit, vdgg_task_rollback and re-apply it as a patch."
      fi
    fi
    # A failed test must go through reflection before more implementation.
    if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "testing" ] \
      && printf '%s' "$GATE_COMMAND" | grep -qE 'vdgg_state_(loop|advance|write)[[:space:]]+[0-9]+[[:space:]]+implementing'; then
      block "A failed test must go through reflection (Step 6-R) before returning to implementing."
    fi
    if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "testing" ]; then
      if printf '%s' "$GATE_COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+[0-9]+[[:space:]]+verified'; then
        if [ -n "${TASK_ALLOWLIST_FILE:-}" ] && [ -f "$TASK_ALLOWLIST_FILE" ]; then
          [ -f "$TASK_GATE_FILE" ] || block "Run vdgg_task_gate successfully before verified."
        fi
        # Plan reconciliation: a task from todo.md needs a record in
        # progress.md of how the diff compares with its plan (vdgg_plan_diff).
        # Discrepancies are allowed; silence is not.
        if ! RECON_PROBLEMS=$(_vdgg_ev_check_reconciliation "$TASKS_DIR/todo.md" "$TASKS_DIR/progress.md" "$(_vdgg_state_get current_task "$STATE_FILE")"); then
          block "$RECON_PROBLEMS"
        fi
        REVIEW_FILE="$CWD/.codex/.vdgg-review-sentinel-${VDGG_ID}-${LOOP_COUNT}"
        [ -f "$REVIEW_FILE" ] || block "Run the Codex review gate with vdgg_review_run before verified."
        MODIFIED=$(grep '^modified=' "$REVIEW_FILE" | sed 's/^modified=//' | head -1)
        [ "$MODIFIED" != "1" ] || block "Review changed files. Go through reflection and retest."
        # Layer 4 consistency via the canonical helper; strict 0/1 exit +
        # stdout tag ("layer4" | "legacy") — no shield needed.
        _VDGG_CX_HOOK_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
        # shellcheck source=vdgg-state.sh
        . "${_VDGG_CX_HOOK_SCRIPT_DIR}/vdgg-state.sh"
        if ! _vdgg_sentinel_class=$(_vdgg_validate_sentinel_fields "$REVIEW_FILE"); then
          block "sentinel invariant violation."
        fi
        # Layer 3 gate-read policy: clean primary must reach clean countersign.
        if ! _vdgg_review_gate_ready "$REVIEW_FILE"; then
          block "Layer 3 countersign missing for a clean primary review. Run vdgg_review_countersign before advancing."
        fi
        if [ "$_vdgg_sentinel_class" = "legacy" ]; then
          printf '%s\n' "VibesDeGoGo! [${VDGG_ID}]: verified via legacy sentinel (pre-Layer-4). Consider re-running review with --review-output for Layer 1 validation." >&2
        fi
        rm -f "$REVIEW_FILE"
      fi
    fi
    ;;
  reflection)
    if [ "$TOOL_NAME" = "apply_patch" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
      while IFS= read -r file_path; do
        [ -n "$file_path" ] || continue
        case "$file_path" in
          "$TASKS_DIR/progress.md"|tasks/vdgg/"$VDGG_ID"/progress.md|"$TASKS_DIR"/investigation-r*.md|tasks/vdgg/"$VDGG_ID"/investigation-r*.md) ;;
          *) block "Reflection may only edit progress.md and investigation-r*.md." ;;
        esac
      done < <(changed_files)
    fi
    # verified is only reachable from testing after review, never from reflection.
    if [ "$TOOL_NAME" = "Bash" ] && printf '%s' "$GATE_COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+[0-9]+[[:space:]]+verified'; then
      block "verified is only reachable from testing after review, not from reflection."
    fi
    # Returning to implementing requires a fresh retry investigation: both
    # investigation-r{loop}.md and progress.md must exist and be newer than the
    # state file (mtime, seconds precision). This stops a blind retry that skips
    # analysis of the failure. Known limit: seconds-precision mtime can tie if a
    # file is written in the same second the state was last written.
    if [ "$TOOL_NAME" = "Bash" ] \
      && printf '%s' "$GATE_COMMAND" | grep -qE 'vdgg_state_(loop|advance|write)[[:space:]]+6[[:space:]]+implementing'; then
      RETRY_INVESTIGATION_FILE="$TASKS_DIR/investigation-r${LOOP_COUNT}.md"
      PROGRESS_FILE="$TASKS_DIR/progress.md"
      [ -f "$RETRY_INVESTIGATION_FILE" ] || block "Write a retry investigation (investigation-r${LOOP_COUNT}.md) before returning to implementing."
      [ -f "$PROGRESS_FILE" ] || block "Update progress.md before returning to implementing."
      STATE_MTIME=$(_vdgg_mtime "$STATE_FILE")
      [ "$(_vdgg_mtime "$RETRY_INVESTIGATION_FILE")" -gt "$STATE_MTIME" ] \
        || block "Write a fresh retry investigation (investigation-r${LOOP_COUNT}.md) before returning to implementing."
      [ "$(_vdgg_mtime "$PROGRESS_FILE")" -gt "$STATE_MTIME" ] \
        || block "Update progress.md before returning to implementing."
    fi
    ;;
  verified|progress|commit)
    if [ "$TOOL_NAME" = "apply_patch" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
      while IFS= read -r file_path; do
        [ -n "$file_path" ] || continue
        path_is_tasks_file "$file_path" && continue
        # No code edits after verification; configured version files may change
        # only during progress/commit, never in verified.
        if [ "$PHASE" != "verified" ] && [ -f "$CWD/.vdgg-target" ]; then
          if grep -E '^VERSION_FILE_[0-9]+_PATH=' "$CWD/.vdgg-target" | sed -E 's/^[^=]*=//' | sed -E 's/^"(.*)"$/\1/' | sed -E "s/^'(.*)'\$/\\1/" | grep -qx "$file_path"; then
            continue
          fi
        fi
        block "No code edits after verification; only progress and configured version files may be edited in phase ${PHASE}."
      done < <(changed_files)
    fi
    # branch-pr workflow forbids committing or pushing directly on the base branch.
    if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "commit" ]; then
      WF=branch-pr; BB=""
      if [ -f "$CWD/.vdgg-target" ]; then
        WF=$( { grep -E '^WORKFLOW=' "$CWD/.vdgg-target" 2>/dev/null || true; } | tail -1 | sed -E 's/^[^=]*=//; s/^"//; s/"$//')
        BB=$( { grep -E '^BASE_BRANCH=' "$CWD/.vdgg-target" 2>/dev/null || true; } | tail -1 | sed -E 's/^[^=]*=//; s/^"//; s/"$//')
        case "$WF" in trunk|branch-pr) ;; *) WF=branch-pr ;; esac
      fi
      if [ "$WF" != "trunk" ]; then
        if [ -z "$BB" ]; then
          BB=$(git -C "$CWD" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
          BB=${BB#origin/}; BB=${BB:-main}
        fi
        CURBR=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        BB_RE=$(printf '%s' "$BB" | sed 's/[^[:alnum:]]/\\&/g')
        if printf '%s' "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+(commit|push)([^[:alnum:]_-]|$)'; then
          if [ "$CURBR" = "$BB" ]; then
            block "branch-pr workflow requires committing/pushing a feature branch and opening a PR, not the base branch."
          fi
          if printf '%s' "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+push' \
            && printf '%s' "$COMMAND" | grep -qE "(^|[^a-zA-Z0-9_/.-])${BB_RE}([^a-zA-Z0-9_/.-]|\$)"; then
            block "branch-pr workflow: do not push the base branch."
          fi
        fi
      fi
    fi
    ;;
  *)
    # Unknown phase: fail closed for mutating tools and Bash. vdgg_state_write
    # also rejects unknown phases at the source; this is defense in depth against
    # a crafted state file.
    if [ "$TOOL_NAME" = "apply_patch" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Bash" ]; then
      block "Unknown workflow phase '${PHASE}'."
    fi
    ;;
esac

# Step 3 read evidence: while investigating, append the files a Bash reader
# (cat, sed -n, head, rg, ...) names to the read log, once no guard refused the
# command. Codex hands the hook no Read tool, so Bash is the only source.
# Recording never refuses a call.
if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "investigating" ]; then
  _vdgg_ev_bash_read_paths "$COMMAND" | _vdgg_ev_record_reads "$READ_LOG" "$CWD" || true
fi

exit 0
