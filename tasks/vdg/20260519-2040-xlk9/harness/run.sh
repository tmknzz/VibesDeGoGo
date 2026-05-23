#!/bin/bash
# VibeDeGoGo! hook 欠陥修正 検証ハーネス
#
# 設計: 「修正後のあるべき挙動」をアサートする。
#   - 未修正スクリプト → 回帰(R*)=PASS / 欠陥(A/B/C/D/E/INIT)=FAIL（バグ存在の証明＝baseline）
#   - 修正完了スクリプト → 全 PASS
#
# 被験体: skills/vibedegogo/scripts/ の各 hook / vdg-state.sh（repo 内、guard2 リテラルは[VibeDeGoGo! Step N Start]）
# 実機・ビルド不要。stdin JSON で hook を駆動し exit code を観測する。

set -u

REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
SCRIPTS="$REPO/skills/vibedegogo/scripts"
HOOK_PRE="$SCRIPTS/vdg-hook-pretool.sh"
HOOK_POST="$SCRIPTS/vdg-hook-posttool.sh"
STATE_SH="$SCRIPTS/vdg-state.sh"
ID="20260519-test-hns0"

PASS=0
FAIL=0
FAILED_CASES=""

ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
ng()   { FAIL=$((FAIL+1)); FAILED_CASES="${FAILED_CASES}\n  - $1"; printf '  FAIL  %s (got exit=%s, want=%s)\n' "$1" "$2" "$3"; }
chk()  { # name actual expected
  if [ "$2" = "$3" ]; then ok "$1"; else ng "$1" "$2" "$3"; fi
}

# 擬似 cwd を作り .claude/.vdg-active + state file を配置。echo で cwd を返す。
mk_cwd() { # step phase loop current_task
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude" "$d/tasks/vdg/$ID"
  echo "$ID" > "$d/.claude/.vdg-active"
  cat > "$d/.claude/.vdg-state-$ID" <<EOF
step=$1
phase=$2
loop_count=$3
current_task=${4:-}
vdg_id=$ID
last_updated=2026-05-19T00:00:00Z
EOF
  echo "$d"
}

# pretool/posttool を JSON 駆動。exit code を返す（標準出力に echo）。
run_hook() { # hook_path json [extra_path]
  local hook="$1" json="$2" extra_path="${3:-}"
  if [ -n "$extra_path" ]; then
    PATH="$extra_path" /bin/bash "$hook" <<<"$json" >/dev/null 2>&1
  else
    /bin/bash "$hook" <<<"$json" >/dev/null 2>&1
  fi
  echo $?
}

j() { jq -nc "$@"; }  # JSON ビルダ（ハーネス側は jq あり）

# jq/brew 抜きの shim PATH（C テスト用）
make_jqless_path() {
  local sd; sd=$(mktemp -d)
  local c
  for c in bash sh cat grep sed cut stat rm date mktemp mv cp head tail tr awk \
           dirname basename ls mkdir touch sleep env printf sort uniq wc find; do
    local p; p=$(command -v "$c" 2>/dev/null) || continue
    ln -sf "$p" "$sd/$c"
  done
  # jq / brew は意図的に入れない
  echo "$sd"
}

echo "REPO=$REPO"
echo "=== 回帰（happy path / 正規遷移は通る = exit 0）==="

# R1: requirements→investigating（requirements.md あり）
CWD=$(mk_cwd 2 requirements 0 "")
: > "$CWD/tasks/vdg/$ID/requirements.md"
JSON=$(j --arg cwd "$CWD" --arg cmd '# [VibeDeGoGo! Step 3 Start] step=3
vdg_state_advance 3 investigating' '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}')
chk "R1 requirements→investigating(req.md有) は通る" "$(run_hook "$HOOK_PRE" "$JSON")" 0

# R2: reflection→implementing（progress.md が state より新しい）= B/A 修正後も塞いではいけない正規ルート
CWD=$(mk_cwd 6 reflection 1 "T1")
sleep 1; : > "$CWD/tasks/vdg/$ID/progress.md"   # state より新しい mtime
: > "$CWD/tasks/vdg/$ID/investigation-r1.md"
JSON=$(j --arg cwd "$CWD" --arg cmd '# [VibeDeGoGo! Step 6 Start] step=6
vdg_state_loop 6 implementing' '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}')
chk "R2 reflection→implementing(progress更新済) は通る" "$(run_hook "$HOOK_PRE" "$JSON")" 0

# R3: testing→verified（sentinel あり modified=0）は通る
CWD=$(mk_cwd 7 testing 0 "T1")
cat > "$CWD/.claude/.vdg-simplify-sentinel-$ID-0" <<EOF
started=1
modified=0
modified_files=
EOF
JSON=$(j --arg cwd "$CWD" --arg cmd '# [VibeDeGoGo! Step 7 Start] step=7
vdg_state_advance 7 verified' '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}')
chk "R3 testing→verified(simplify modified=0) は通る" "$(run_hook "$HOOK_PRE" "$JSON")" 0

# R4: implementing 中のコードファイル編集は許可（exit 0）
CWD=$(mk_cwd 6 implementing 0 "T1")
JSON=$(j --arg cwd "$CWD" --arg fp "$CWD/src/foo.swift" '{tool_name:"Edit",cwd:$cwd,tool_input:{file_path:$fp}}')
chk "R4 implementing でコード編集は通る" "$(run_hook "$HOOK_PRE" "$JSON")" 0

echo "=== A: reflection→verified バイパス封じ（修正後 exit 2）==="
CWD=$(mk_cwd 6 reflection 1 "T1")
JSON=$(j --arg cwd "$CWD" --arg cmd '# [VibeDeGoGo! Step 7 Start] step=7
vdg_state_advance 7 verified' '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}')
chk "A reflection で verified 遷移は exit 2" "$(run_hook "$HOOK_PRE" "$JSON")" 2

echo "=== B: reflection progress.md mtime ガード（5→6 是正後 exit 2）==="
CWD=$(mk_cwd 6 reflection 1 "T1")
# progress.md を state より「古い」(= reflection 中に未更新) にする
: > "$CWD/tasks/vdg/$ID/progress.md"; sleep 1
: > "$CWD/tasks/vdg/$ID/investigation-r1.md"
touch "$CWD/.claude/.vdg-state-$ID"   # state を後で touch → progress が古い
JSON=$(j --arg cwd "$CWD" --arg cmd '# [VibeDeGoGo! Step 6 Start] step=6
vdg_state_loop 6 implementing' '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}')
chk "B reflection 未更新で 6 implementing は exit 2" "$(run_hook "$HOOK_PRE" "$JSON")" 2

echo "=== D: declare/requirements の TASKS_DIR 外編集ブロック（修正後 exit 2）==="
CWD=$(mk_cwd 1 declare 0 "")
OUT=$(mktemp -d)/outside.txt
JSON=$(j --arg cwd "$CWD" --arg fp "$OUT" '{tool_name:"Write",cwd:$cwd,tool_input:{file_path:$fp}}')
chk "D declare で TASKS_DIR 外 Write は exit 2" "$(run_hook "$HOOK_PRE" "$JSON")" 2

CWD=$(mk_cwd 2 requirements 0 "")
JSON=$(j --arg cwd "$CWD" --arg fp "$CWD/tasks/vdg/$ID/requirements.md" '{tool_name:"Write",cwd:$cwd,tool_input:{file_path:$fp}}')
chk "D requirements で TASKS_DIR 内 Write は通る(回帰)" "$(run_hook "$HOOK_PRE" "$JSON")" 0

CWD=$(mk_cwd 1 declare 0 "")
JSON=$(j --arg cwd "$CWD" --arg cmd '# [VibeDeGoGo! Step 2 Start] step=2
vdg_state_advance 2 requirements' '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}')
chk "D declare で Bash(vdg_state_*) は通る(回帰)" "$(run_hook "$HOOK_PRE" "$JSON")" 0

echo "=== C: jq 不在フェイルクローズ + setup ホワイトリスト（修正後）==="
JQLESS=$(make_jqless_path)
CWD=$(mk_cwd 6 implementing 0 "T1")
JSON=$(j --arg cwd "$CWD" --arg cmd 'brew install jq' '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}')
chk "C jq不在: brew install jq は通る(whitelist)" "$(run_hook "$HOOK_PRE" "$JSON" "$JQLESS")" 0
JSON=$(j --arg cwd "$CWD" --arg cmd 'rm -rf /tmp/somewhere' '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}')
chk "C jq不在: 一般コマンドは exit 2(fail-close)" "$(run_hook "$HOOK_PRE" "$JSON" "$JQLESS")" 2
JSON=$(j --arg cwd "$CWD" --arg cmd 'brew install jq' '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}')
chk "C jq不在(posttool): brew install jq は通る" "$(run_hook "$HOOK_POST" "$JSON" "$JQLESS")" 0
JSON=$(j --arg cwd "$CWD" --arg cmd 'echo hi' '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}')
chk "C jq不在(posttool): 一般コマンドは exit 2" "$(run_hook "$HOOK_POST" "$JSON" "$JQLESS")" 2

echo "=== E: 8→5 で loop_count=0 リセット（vdg-state.sh）==="
D=$(mktemp -d)
(
  export VDG_CWD="$D"
  source "$STATE_SH"
  vdg_state_init >/dev/null 2>&1
  id=$(vdg_get_id)
  # step=8 phase=progress loop=7 の fixture を置く。
  cat > "$D/.claude/.vdg-state-$id" <<EOF
step=8
phase=progress
loop_count=7
current_task=T2
vdg_id=$id
last_updated=2026-05-19T00:00:00Z
EOF
  vdg_state_advance 5 task-selected >/dev/null 2>&1
  grep '^loop_count=' "$D/.claude/.vdg-state-$(cat "$D/.claude/.vdg-active")" | cut -d= -f2
) > /tmp/_e_out 2>/dev/null
chk "E 8→5 後 loop_count=0" "$(cat /tmp/_e_out)" 0

# E回帰: reflection(6)→implementing(6) loop は +1（リセットされない）
D=$(mktemp -d)
(
  export VDG_CWD="$D"
  source "$STATE_SH"
  vdg_state_init >/dev/null 2>&1
  id=$(vdg_get_id)
  cat > "$D/.claude/.vdg-state-$id" <<EOF
step=6
phase=reflection
loop_count=2
current_task=T2
vdg_id=$id
last_updated=2026-05-19T00:00:00Z
EOF
  vdg_state_loop 6 implementing >/dev/null 2>&1
  grep '^loop_count=' "$D/.claude/.vdg-state-$(cat "$D/.claude/.vdg-active")" | cut -d= -f2
) > /tmp/_e2_out 2>/dev/null
chk "E回帰 reflection→implementing は loop+1(=3)" "$(cat /tmp/_e2_out)" 3

echo "=== INIT: 旧残骸掃除（vdg_state_init）==="
D=$(mktemp -d)
(
  export VDG_CWD="$D"
  source "$STATE_SH"
  mkdir -p "$D/.claude"
  echo "old" > "$D/.claude/.vdg-active"
  : > "$D/.claude/.vdg-error-pending"
  : > "$D/.claude/.vdg-simplify-sentinel-old-0"
  : > "$D/.claude/.vdg-step-block-old"
  vdg_state_init >/dev/null 2>&1
  remain=0
  [ -f "$D/.claude/.vdg-error-pending" ] && remain=$((remain+1))
  ls "$D/.claude/".vdg-simplify-sentinel-* >/dev/null 2>&1 && remain=$((remain+1))
  ls "$D/.claude/".vdg-step-block-* >/dev/null 2>&1 && remain=$((remain+1))
  echo "$remain"
) > /tmp/_init_out 2>/dev/null
chk "INIT 旧残骸が掃除される(残数0)" "$(cat /tmp/_init_out)" 0

echo
echo "================ RESULT ================"
printf 'PASS=%d  FAIL=%d\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'FAILED:%b\n' "$FAILED_CASES"
  exit 1
fi
echo "ALL GREEN"
exit 0
