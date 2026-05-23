# investigation — VibeDeGoGo! hook ロジック欠陥

id: 20260519-2040-xlk9 / 調査者: エージェント（実コード精読、推測なし）

## 1. 関連ファイル一覧

| パス（repo 相対） | 役割 |
|---|---|
| `skills/vibedegogo/scripts/vdg-state.sh` | state file 操作ヘルパー（sourced）。`vdg_state_init/read/write/advance/loop/clear`、`_vdg_check_step_transition` |
| `skills/vibedegogo/scripts/vdg-hook-pretool.sh` | PreToolUse hook。phase 別 Edit/Write/Bash/Agent ブロック、guard2/4/5、simplify sentinel 検証、loop上限 |
| `skills/vibedegogo/scripts/vdg-hook-posttool.sh` | PostToolUse hook。Bash エラー検出 → `.vdg-error-pending`、testing 中の simplify sentinel 生成・modified 記録 |
| `skills/vibedegogo/scripts/vdg-hook-stop.sh` | Stop hook。サイクル中の無宣言ターン終了をブロック |
| `skills/vibedegogo/SKILL.md` | フロー正本。Step 番号・phase 表・遷移コマンド定義（hook 期待値の根拠） |

## 2. 既存実装パターン

- **phase 分岐**: pretool は `case "$PHASE" in declare|requirements) ... investigating|planning) ... task-selected) ... implementing|testing) ... reflection) ... verified|progress|commit) ... esac`（`vdg-hook-pretool.sh:179-309`）。各 case で許可/ブロックを決める。
- **遷移コマンド検出**: `echo "$COMMAND" | grep -qE 'vdg_state_(advance|loop|write)[[:space:]]+<step>[[:space:]]+<phase>'` で Bash コマンド本体から遷移を判定。
- **exit 2 = ブロック**: Claude Code hook 仕様で exit 2 のみツール阻止＋stderr フィードバック。それ以外の非ゼロは非ブロッキング（ツール実行される）。
- **step 連続性**: `_vdg_check_step_transition`（`vdg-state.sh:56-79`）が +0 / +1 / 8→5 / 7→6 のみ許可。
- **phase↔step 対応**（SKILL.md phase 表 / 出力フォーマット）: declare=1, requirements=2, investigating=3, planning=4, task-selected=5, **implementing=6**, testing=7, reflection=6（Step 6-R）, verified=7末, progress=8, commit=9。

## 3. 影響範囲（欠陥ごとに呼び出し側まで特定）

### A（重大）reflection→verified バイパス
- simplify sentinel / 再テスト強制の検証は `vdg-hook-pretool.sh:221-250` の `implementing|testing)` case 内、かつ `[ "$PHASE" = "testing" ]` ガード（`:229`, `:234`）でのみ発火。
- `reflection)` case（`:252-278`）は Edit/Write を progress.md に限定し、`5 implementing` 遷移しか見ない。**`verified` 遷移を一切検証しない**。
- `_vdg_check_step_transition`: reflection(step6)→verified(step7) は +1 で許可（`:65`）。
- 帰結: `testing → vdg_state_advance 6 reflection`（7→6 許可）→ phase=reflection → `vdg_state_advance 7 verified`（6→7 許可、reflection case は素通し）で **simplify modified=1 ブロックと再テストを完全回避**。SKILL.md:422-426 の「失敗系は必ず reflection 経由」物理強制が破れている。

### B（重大）reflection progress.md 更新強制が死亡
- `vdg-hook-pretool.sh:264`: `grep -qE 'vdg_state_(loop|advance|write)[[:space:]]+5[[:space:]]+implementing'`。
- SKILL.md:271 の正規コマンドは `vdg_state_loop 6 implementing`（implementing=step6、phase 表と一致）。SKILL.md:264 周辺の本文も `6 implementing` を指す。
- 帰結: ドキュメント通り `6 implementing` で戻すと正規表現に**マッチせず**、`:266-275` の progress.md 存在チェック＋mtime チェックが**一度も発火しない**。reflection の「失敗要因を progress.md に書いてから戻れ」物理強制（SKILL.md:274）が dead code。

### C（重大）jq 不在フェイルオープン
- `vdg-hook-pretool.sh:8-16` / `vdg-hook-posttool.sh:9-17`: jq 無し → `exit 1`。
- exit 1 は非ブロッキング → **ツールは実行される**。brew install 完走までの間、全 phase ガード・guard2/4/5・sentinel 検証が無音で無効。
- 単純に exit 2 にすると `brew install jq` 自体も Bash でブロックされデッドロック（install できず永久ブロック）。→ ホワイトリスト方式が必要。

### D（中）declare/requirements でコード編集素通し
- `vdg-hook-pretool.sh:180-197` `declare|requirements)` case は Agent ブロック＋requirements.md 存在チェックのみ。**Edit/Write/Bash への制約なし**。
- 対照: `investigating|planning)`（`:199-211`）は TASKS_DIR 外 Edit/Write を exit 2。`task-selected)`（`:213-219`）は Edit/Write 全ブロック。
- 帰結: Step 1〜2 でソースコードを実装可能。「investigate/plan 前に実装させない」物理強制が declare/requirements で欠落。

### E（中）loop_count タスク跨ぎ非リセット
- `vdg-state.sh:182-210` `vdg_state_advance`: 8→5 戻り時、`current_loop` を読み出し `vdg_state_write` にそのまま渡す（`:202-209`）。リセットなし。
- `vdg_state_loop`（`:212-249`）のみ +1。`vdg_state_clear`（`:251`）でのみ消える。
- 帰結: T1 で loop=5 → T2 開始時 loop=5。SKILL.md:267「**同タスク**で loop_count>3 でアーキ検討必須」「99 上限」が累積判定になりタスク跨ぎで誤発火。

### init 汚染掃除
- `vdg-state.sh:83-115` `vdg_state_init`: 旧 active を**警告するだけ**（`:93-97`）。`.vdg-error-pending` / `.vdg-simplify-sentinel-*` / `.vdg-step-block-*` を掃除しない。
- 対照: `vdg_state_clear`（`:269-272`）は掃除する。
- 帰結: clear せず放棄したセッションの残骸を新 init セッションが継承（初手で 【エラー認識】 要求等）。

## 4. 過去の類似実装 / 教訓

- `git log`: 単一コミット `ec86db6 docs: publish VibeDeGoGo! workflow`（公開直後、修正履歴なし）。過去の retry なし。
- 設計教訓（コード内コメント `vdg-hook-pretool.sh:113-131`）: guard2 は transcript タイミング非信頼性のため検証対象を assistant text → `tool_input.command` へ移行済み。**しかし error 認識検証（`:74-89`）は旧 transcript 方式のまま残存**（軽微3件のうち1件、今回スコープ外）。
- B の `5 vs 6` は SKILL.md と hook の番号定義不一致。SKILL.md phase 表（implementing=Step6）が正本、hook 側が誤り。

## 5. 想定される副作用 / リスク

- **A 修正**: reflection から verified を塞ぐと、正規ルート（reflection→`vdg_state_loop 6 implementing`→testing→verified）は影響なし。reflection から implementing 以外の遷移を全面禁止すると 8→5 等の正規遷移と干渉しないか要確認 → reflection からの正規遷移は `6 implementing`（loop）と `7 testing`（再テストのため？）のみ。SKILL.md 上 reflection の出口は `vdg_state_loop 6 implementing` 一択。verified への直行のみピンポイントで塞ぐのが最小риск。
- **B 修正**: `5`→`6` に変えるだけ。happy path は `6 implementing` が正規なので、これでようやく意図通り発火。誤って `5` のままの別経路依存はない（grep 確認: `5 implementing` 参照は当該1箇所のみ）。
- **C 修正**: ホワイトリスト正規表現が広すぎると jq 不在時に任意 Bash が通る穴になる。`brew (install|reinstall) ...jq` / `apt.*jq` / 既存の `command -v jq` 程度に限定。狭すぎると install できずデッドロック。テストで両端を確認。
- **D 修正**: declare phase は Step 1（init 直後の宣言）。requirements phase は Step 2（requirements.md 執筆）。TASKS_DIR 配下のみ許可にすると requirements.md 執筆は通る（TASKS_DIR 内）。Step 1 で Bash（vdg_state_init/advance）は必要 → Bash はブロックしない、Edit/Write のみ TASKS_DIR 限定（investigating/planning と同一ポリシー）。
- **E 修正**: 8→5 でのみ loop=0。7→6（reflection）や 6→6（loop）には影響させない。`vdg_state_advance` 内で current→next が 8→5 のときだけ 0 を渡す分岐。後方互換: state file 形式不変。
- **共通**: happy path 回帰がないことを擬似入力テストで担保。実機不要（hook は stdin JSON で駆動できる）。

## 6. 制約条件

- bash 3.2（macOS 標準）互換。`[[ ]]` / `=~` は可、連想配列等の bash4 機能は不可。
- exit code 規約: ブロックは exit 2 のみ。それ以外は素通し扱い。
- guard2（registered legacy hook が enforcement）: Step 2 以降の `vdg_state_advance|loop|write` 実行 Bash には `[VibeDeGoGo! Step N Start]` リテラルが必要（VibeDeGoGo! リテラルではない。enforcing hook がlegacy formation workflow のため）。
- `set -euo pipefail` 下。grep no-match の非ゼロは `|| true` で吸収する既存パターンを踏襲。
- legacy formation workflowsは変更禁止（requirements Constraints）。

## 7. テスト戦略（テスタブル・実機不要）

各 hook は stdin に JSON を流して exit code と stderr を観測できる。検証ハーネス（bash スクリプト）を tasks ディレクトリに置き、ケースごとに:

1. **A**: state を phase=reflection, step=6 に作り、`vdg_state_advance 7 verified` を含む Bash tool_input JSON を pretool に流す → exit 2 期待。phase=reflection で `vdg_state_loop 6 implementing`（progress.md 更新済み）→ exit 0 期待（A が B と干渉しないこと）。
2. **B**: phase=reflection, step=6, progress.md を state file より古い mtime → `vdg_state_loop 6 implementing` → exit 2。progress.md を touch（新しい）→ exit 0。
3. **C**: PATH から jq を外した環境で pretool に `brew install jq` Bash → exit 0（通過）、任意の他コマンド → exit 2。
4. **D**: phase=declare で TASKS_DIR 外への Write JSON → exit 2、TASKS_DIR 内 → exit 0。phase=requirements 同様。Bash（vdg_state_*）は exit 0。
5. **E**: state を step=8 にし `vdg_state_advance 5 task-selected`（loop_count=7 の状態）→ 実行後 state の loop_count=0 を確認。
6. **init掃除**: ダミーの `.vdg-error-pending` 等を置いて `vdg_state_init` → 消えていることを確認。
7. **回帰**: 正規 happy path の代表遷移（1→2→3→4→5→6→7→verified→8→9）を順に流し、いずれも exit 0（ブロックされない）ことを確認。

検証は擬似 cwd（一時ディレクトリに `.claude/.vdg-active` + state file を作る）で hook を直接 `bash script.sh < input.json` 起動。実機・ビルド不要。
