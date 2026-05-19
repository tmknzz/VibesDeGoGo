# [VibeGoGo 参照: state file ヘルパー関数リファレンス]

このファイルは SKILL.md 本体から切り出された詳細補足。

## state file 構造（v2: ID対応）

各VibeGoGoセッションは一意のID（`YYYYMMDD-HHMM-xxxx`）で管理される。**state file と tasks ディレクトリは ID ごとに分離されるため、前回の tasks データは温存される**。ただし `.fop-active` は新ID で上書きされる（前回IDは警告ログに出るだけ）。

```
.claude/.fop-active              ← 現在アクティブなVibeGoGoのID（新ID起動で上書き）
.claude/.fop-state-{id}          ← IDに対応するstate file（ID別）
tasks/fop/{id}/todo.md           ← IDごとのタスク管理（ID別）
tasks/fop/{id}/progress.md
tasks/fop/{id}/investigation.md  ← Step 3 で生成される深い調査レポート
```

state file は KEY=VALUE 形式:

```
step=<1..9>
phase=<declare|requirements|investigating|planning|task-selected|implementing|testing|reflection|verified|progress|commit>
loop_count=<非負整数、Step 6↔7 往復回数>
current_task=<Step 5 で選択した todo.md 内のタスク識別子（行頭タイトル等）>
fop_id=<YYYYMMDD-HHMM-xxxx>
last_updated=<ISO8601 UTC>
```

## ヘルパー関数一覧

```bash
source $HOME/.claude/skills/vibegogo/scripts/fop-state.sh

fop_state_init                                       # ID生成＋初期化（step=1, phase=declare, loop_count=0）
fop_state_write <step> <phase> <loop_count> [task]   # 明示書き込み（第4引数は省略可。省略時は既存値を引き継ぐ）
fop_state_advance <step> <phase>                     # 通常進行（連続性チェック付き）
fop_state_loop <step> <phase>                        # ループ時（loop_count +1、連続性チェック付き）
fop_state_read                                       # 現在の state を stdout に吐く（grep で拾う用途）
fop_state_clear                                      # 完了時（state file＋active file削除）
fop_get_tasks_dir                                    # 現在のtasksディレクトリパスを取得
fop_get_id                                           # 現在のVibeGoGoIDを取得
```

## Step 連続性チェック（ガード1対策）

`fop_state_advance` / `fop_state_loop` は前後 step の連続性を検証する。許可される遷移は以下のみ:

- `+0` / `+1`(同 phase 内の遷移、次 step への進行)
- `8→5`（progress→task-selected、未完了タスクあり時の戻り）
- `7→6`（reflection / implementing 往復、`fop_state_loop` 経由）

上記以外の遷移（例: `1→6`、`5→2` など）は `return 1` でブロックされる。

**注**: `fop_state_init` は `mkdir -p tasks/fop/{id}/` までやるが、`todo.md` / `progress.md` / `investigation.md` の **ファイル本体は対応する Step でエージェント／subagentが生成する** 責任。ディレクトリだけ先にある状態になる。

## エージェントの自律制限

1. **`.fop-state-*` / `.fop-active` 手動編集禁止**: state file は `fop_state_*` 関数経由でのみ操作する（直接 `echo > .claude/.fop-state-*` や Edit での書き換えは禁止）
2. **hook exit 2 迂回禁止**: hook が exit 2 で停止した場合、phase を手で書き換えたり hook を無効化したりして先に進めず、原因を修正してから再実行する
3. **Step 飛ばし禁止**: 連続性チェックで物理ブロックされる以外にも、エージェント自身が「効率優先」で Step を飛ばさない。Step 3 の深い調査を省略すると Step 4 のプランニング品質が落ちる
4. **コードロジック変更は Step 6 でしか行わない**: Step 8 (`progress`) / Step 9 (`commit`) phase で hook が許可するのは `progress.md` 追記と `.fop-target` の `VERSION_FILE_*_PATH` ファイル（バージョン番号更新等）のみ。実装ファイル（.swift / .js / .ts 等のロジック変更）は Step 6 でしか書かない。「commit 直前のちょい変更」「動作確認用のパラメータ調整」も含めて、ロジック変更したくなったら新サイクルを起動して Step 6 から正規ルートで実施する（エージェント自身がやる場合もsubagentに委任する場合も同じ）

## simplify sentinel ファイルのライフサイクル

`testing → verified` 遷移を物理強制するための痕跡ファイル。Step 7（testing phase）で simplify スキルを起動したかどうか、起動後に修正（Edit/Write）が入ったかどうかを記録する。

### 命名規約

```
$CWD/.claude/.fop-simplify-sentinel-{fop_id}-{loop_count}
```

- 例: `.claude/.fop-simplify-sentinel-20260506-0138-dxuq-3`
- 命名は既存のフラグファイル機構（`.fop-error-pending`, `.fop-step-block-*`）と統一性を持たせている
- `fop_id` で並走する他セッションと衝突しないようにし、`loop_count` でサイクル毎に独立させる

### 内容スキーマ（KEY=VALUE 多行）

| キー | 型 | 必須 | 説明 |
|------|----|------|------|
| `started` | `0\|1` | 必須 | simplify スキルが起動された痕跡（起動時に `1` を書く） |
| `started_at` | ISO8601 UTC 文字列（例: `2026-05-06T01:00:00Z`） | 必須 | simplify 起動時刻 |
| `modified` | `0\|1` | 必須 | simplify 起動後に同 loop_count 中に Edit/Write が起こったか（初期値 `0`、検出時 `1` に更新） |
| `modified_files` | カンマ区切りのファイルパス | `modified=1` のときのみ | Edit/Write の対象ファイル一覧（追記） |

読み出しは既存規約に揃え、`grep "^key=" | cut -d= -f2-` で取り出す。

### 生成タイミング

- **PostToolUse hook**（`fop-hook-posttool.sh`）が、`phase=testing` 中に Skill tool で `simplify` 起動を検出したとき、新規作成する
- 既に同 `loop_count` の sentinel が存在する場合は温存（`started=1` / `started_at` を尊重）

### 更新タイミング

- 同 `loop_count` 中の Edit/Write を PostToolUse hook が検出したとき、`modified=1` と `modified_files=<追加パス>` を追記する
- simplify が修正を入れた痕跡として、PreToolUse hook の `fop_state_advance 7 verified` ガードがこれを参照する

### 削除タイミング

1. **verified ガード通過後**: PreToolUse hook が `fop_state_advance 7 verified` を検証し、sentinel が存在し `modified=0` で通過した直後に hook 末尾で `rm -f` する（次サイクルへ持ち越さない）
2. **`fop_state_loop` での `loop_count` 更新時**: reflection→implementing 遷移で `loop_count` が +1 されるとき、旧 `loop_count` の sentinel を `rm -f` する（古い sentinel が新サイクルに混入しないように）
3. **`fop_state_clear` 時**: セッション完了時に `.fop-simplify-sentinel-*` を一掃する（既存の `.fop-step-block-*` / `.fop-error-pending` 一掃と同じ `rm -f` パターン）

### 設計意図

- 既存のフラグファイル機構（`.fop-error-pending`, `.fop-step-block-*`）と命名・形式（`KEY=VALUE` 多行）・クリーンアップ手段（`fop_state_clear` 一掃）を揃え、認知コストを最小化する
- `fop_id` + `loop_count` のスコープにより、並走セッション・サイクル間での衝突を物理的に避ける
- 「simplify 起動の有無」と「simplify 後の修正の有無」を 2 軸で記録することで、`fop_state_advance 7 verified` ガードが「未起動ブロック」と「修正あり → reflection 経路強制」の両方を判定できる
