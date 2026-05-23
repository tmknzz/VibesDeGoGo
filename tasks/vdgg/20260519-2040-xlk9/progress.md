# progress — VibesDeGoGo! hook ロジック欠陥修正

id: 20260519-2040-xlk9

## T1: 検証ハーネス構築（擬似cwd・JSON駆動・exit/stderr アサート）
状態: 完了
- run.sh 実装（擬似cwd・JSON駆動・exit assert・16ケース）
- reflection loop1: REPO 段数 ×5→×4 修正、E subshell 防御
- simplify: dead fallback `|| echo "ERR"` 指摘 → 除去（tasks配下のため sentinel modified=0、設計通り reflection 非強制、再テストで分類不変を確認）
- baseline 検証成立: PASS=7（回帰全緑）/ FAIL=9（欠陥9件が想定 exit で赤）。T2-T4 修正後に全 PASS が受け入れ条件
- 検証コマンド: `bash tasks/vdgg/20260519-2040-xlk9/harness/run.sh`

## T2: vdgg-state.sh — E（8→5 で loop_count=0）+ init 残骸掃除
状態: 未着手

## T3: vdgg-hook-pretool.sh — A（reflection→verified ブロック）+ B（5→6）+ D（declare/requirements Edit/Write 限定）
状態: 未着手

## T4: jq フェイルクローズ + セットアップ Bash ホワイトリスト（pretool & posttool）
状態: 未着手

---

# Reflection — loop 0 → 1（T1 harness 失敗）

## 0. researcher 起動結果と investigation-r0.md 不在の理由（新発見・第7欠陥）

reflection §0 規約に従い Explore researcher を very thorough で起動した。researcher は `investigation-r0.md` を Write しようとしたが、**registered legacy PreToolUse hook の reflection case（progress.md 以外の Edit/Write を exit 2）に subagent の Write もブロックされ、生成不能**だった。

→ **第7の設計欠陥**: SKILL.md「Step 6-R」は「reflection 中に researcher が `investigation-r{loop_count}.md` を Write 生成」を必須としているが、reflection phase の hook は progress.md 以外の Write を全ブロックする。**researcher 成果物の物理生成が hook と矛盾し常に不可能**。これは VibesDeGoGo!/legacy workflow commonの構造欠陥。今回の合意スコープ（A/B/C/D/E/init）外のため、本サイクルでは扱わずユーザーに別途握る。researcher 解析の実体は下記に全文保全する（情報は失っていない）。

### researcher 解析全文（保全）
- **REPO パス**: run.sh:13 `cd "$(dirname "$0")/../../../../.."` は ×5 段で `/Users/jonji/GitHub/tamekuniz` を指す。正は ×4 段 `../../../..` → `/Users/jonji/GitHub/tamekuniz/VibesDeGoGo!`。全16ケース exit=127 の単一根本原因。
- **E/INIT subshell**: `source "$STATE_SH"` も同 REPO バグ影響下。REPO 修正で解消。VDGG_CWD は `export` で渡し vdgg-state.sh:10 `:=` が尊重 → ✓。E subshell 末尾 grep は match なし時 exit 1 を出しうる → `|| echo 0` 防御を足すと堅牢（path 修正後は通常 match するので必須ではないが安全側）。
- **B mtime**: 被験体 pretool:272 は `-le`（同値も exit 2）。ハーネスの「progress 作成→sleep→state touch」で progress<state を作る意図は比較式と整合。ただし B 欠陥本体は被験体 pretool:264 の `5 implementing`（正は `6`）で T3 修正対象。
- **R3 sentinel**: pretool:234-248 のロジック（modified 行 grep / 通過時 rm）と mk_cwd 後 sentinel 配置順は整合 ✓。
- **C shim**: 被験体が jq 不在経路で使う grep/sed/cat/cut/stat/rm は shim に網羅 ✓。jq チェック本体（pretool:8-16 exit 1）は T4 修正対象。
- **guard2 リテラル**: 被験体 pretool:136 は `【VibesDeGoGo! Step N 開始】`。ハーネス R1/R2/R3/A/B は対応リテラルを内包、D の遷移なしケースは意図的に無し → 全ケース整合 ✓。
- **bash3.2 / set -u**: `[[ ]]`/`<<<`/`${x:-}` すべて 3.2 互換、未定義変数防御済み ✓。

## 1. Root Cause Investigation（失敗要因）
全16ケース exit=127。単一根本原因は `run.sh:13` の相対パス遡上段数誤り（×5）。`REPO` が `/Users/jonji/GitHub/tamekuniz` になり `$SCRIPTS/*.sh` が存在せず `bash <不在> ` が 127 を返した。E/E回帰/INIT は同 REPO 由来で `$STATE_SH` source 失敗（関数未定義）。これは被験体スクリプトの欠陥ではなく **T1 ハーネス自身の実装欠陥**。投入ログ: ハーネス出力 `REPO=/Users/jonji/GitHub/tamekuniz` + 全ケース `got exit=127`。

## 2. Pattern Analysis（動作リファレンスとの差異）
- 正しく動く参照: `dirname run.sh` = `.../VibesDeGoGo!/tasks/vdgg/<id>/harness`。VibesDeGoGo! ルートまでは harness→`<id>`→vdgg→tasks→VibesDeGoGo! の **4 段**。
- 現状との差異: コードは 5 段（`../`×5）。1 段過剰で repo の親（tamekuniz）へ突き抜けた。
- 前ループで変えた点: 無し（loop 0、初実装の素のミス）。

## 3. Hypothesis（単一仮説）
`run.sh:13` の `../../../../..`（5 段）を `../../../..`（4 段）に直せば `REPO` が `.../VibesDeGoGo!` になり、`$SCRIPTS`/`$STATE_SH` が解決、127 が解消して baseline 分類（回帰=PASS / 欠陥=FAIL）が成立する。E subshell に `|| echo 0` を足すのは安全側の二次防御。これが原因と考える理由: 全ケース一律 127 かつ `REPO` 出力が親ディレクトリを示しており、パス解決失敗以外の症状（個別ロジック差）が出ていないため。

## 4. Implementation 計画（単一修正・T1 スコープ限定）
次の implementing で **`run.sh` のみ** 修正（current_task=T1 のスコープ厳守。hook 側 B/A/D/C/E/init は T2-T4）:
1. `run.sh:13`: `../../../../..` → `../../../..`
2. `run.sh` E テスト subshell 末尾の `grep ... | cut ...` を `|| echo 0` で防御（match なし時の空出力/exit1 吸収、安全側）
「ついで」改善はしない。hook 修正は持ち込まない。再テスト（baseline 再実行）で「回帰群 PASS / 欠陥群 FAIL / E回帰 PASS」が出れば T1 verified 条件成立。
