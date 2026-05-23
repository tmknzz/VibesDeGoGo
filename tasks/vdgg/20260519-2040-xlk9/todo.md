# todo — VibesDeGoGo! hook ロジック欠陥修正

id: 20260519-2040-xlk9

- [ ] T1: 検証ハーネス構築（擬似cwd・JSON駆動・exit/stderr アサート）
    - **対象ファイル**: `tasks/vdgg/20260519-2040-xlk9/harness/run.sh`（新規）
    - **編集対象**: 新規作成。一時 cwd に `.claude/.vdgg-active` + `.vdgg-state-{id}` を生成し、`bash <hook> < input.json` を起動して exit code と stderr を期待値比較するアサート関数 `expect_exit` / `expect_block` / `expect_pass`。回帰ケース（happy path 1→2→3→4→5→6→7→verified→8→9）を含む。
    - **期待挙動**: `bash harness/run.sh` で全ケースの PASS/FAIL を一覧出力。終了コードは1件でも FAIL があれば非ゼロ。
    - **検証コマンド**: `bash tasks/vdgg/20260519-2040-xlk9/harness/run.sh`（未修正スクリプトに対し回帰ケースが全 PASS、欠陥ケースは想定通り FAIL=未修正、を baseline として確認）
    - **備考**: ハーネスは `skills/vibesdegogo/scripts/` の各 hook を被験体にする。jq 必須ケースは PATH 操作で jq を隠す。
- [ ] T2: vdgg-state.sh — E（8→5 で loop_count=0）+ init 残骸掃除
    - **対象ファイル**: `skills/vibesdegogo/scripts/vdgg-state.sh`
    - **編集対象**: `vdgg_state_advance`（`:182-210`）— current_step=8 かつ next_step=5 のとき渡す loop を 0 にする分岐を追加。`vdgg_state_init`（`:83-115`）— active 警告（`:93-97`）の後に `.vdgg-error-pending` / `.vdgg-simplify-sentinel-*` / `.vdgg-step-block-*` を `rm -f` する（`vdgg_state_clear:269-272` と同じ掃除）。
    - **期待挙動**: before=8→5 で loop_count 据え置き / after=0 リセット。before=init が残骸放置 / after=掃除。7→6・6→6 等は不変。
    - **検証コマンド**: `bash tasks/vdgg/20260519-2040-xlk9/harness/run.sh`（E ケース・init掃除ケース・回帰）
    - **備考**: state file 形式・関数シグネチャ不変。bash3.2 互換。
- [ ] T3: vdgg-hook-pretool.sh — A（reflection→verified ブロック）+ B（5→6）+ D（declare/requirements Edit/Write 限定）
    - **対象ファイル**: `skills/vibesdegogo/scripts/vdgg-hook-pretool.sh`
    - **編集対象**:
      - A: `reflection)` case（`:252-278`）に、Bash で `vdgg_state_(advance|loop|write)[[:space:]]+[0-9]+[[:space:]]+verified` を検出したら exit 2 する分岐を追加（reflection からは implementing 経由のみ）。
      - B: `:264` の `[[:space:]]+5[[:space:]]+implementing` を `[[:space:]]+6[[:space:]]+implementing` に是正。
      - D: `declare|requirements)` case（`:180-197`）に、`investigating|planning)` と同型の「Edit/Write は TASKS_DIR 配下のみ許可、外は exit 2」分岐を追加（Bash・Agent は現状維持）。
    - **期待挙動**: A=reflection で verified 遷移 exit 2 / 正規 reflection→`6 implementing` は通る。B=`6 implementing` で progress.md mtime チェック発火。D=declare/requirements の TASKS_DIR 外 Edit/Write が exit 2。
    - **検証コマンド**: `bash tasks/vdgg/20260519-2040-xlk9/harness/run.sh`（A/B/D ケース・回帰）
    - **備考**: happy path（reflection→`vdgg_state_loop 6 implementing`）を塞がないこと。guard2 既存挙動に触れない。
- [ ] T4: jq フェイルクローズ + セットアップ Bash ホワイトリスト（pretool & posttool）
    - **対象ファイル**: `skills/vibesdegogo/scripts/vdgg-hook-pretool.sh`、`skills/vibesdegogo/scripts/vdgg-hook-posttool.sh`
    - **編集対象**: 両ファイル先頭の jq 不在分岐（pretool `:8-16` / posttool `:9-17`）。jq 不在時、入力 JSON から tool_name/command を **jq 無しで素朴に判定**（grep/sed フォールバック）し、Bash かつコマンドが jq セットアップ系（`brew[[:space:]]+(install|reinstall)[^|;&]*\bjq\b` 等の限定パターン）なら exit 0、それ以外は **exit 2**（フェイルクローズ）。
    - **期待挙動**: before=jq 不在で exit 1（全ガード無効・ツール実行）。after=jq 不在で `brew install jq` のみ通過、他は exit 2 ブロック。
    - **検証コマンド**: `bash tasks/vdgg/20260519-2040-xlk9/harness/run.sh`（C ケース: PATH から jq 隠蔽 → install Bash 通過 / 他コマンド exit 2）
    - **備考**: ホワイトリストは狭く保つ（jq 不在時に任意 Bash を通す穴を作らない）。jq 無し JSON 解析は最小限（tool_name と command の抽出のみ）。
