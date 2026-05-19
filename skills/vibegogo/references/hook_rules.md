# [VibeGoGo 参照: pre-tool hook ルール]

このファイルは SKILL.md 本体から切り出された詳細補足。

## pre-tool hook ルール

実装側の挙動を正直に列挙する（表記と実装が一致するように記述）。

**全 phase 共通（ガード2/4 対策、phase 分岐前に実行）**:
- **state file 保護（ガード4）**: `.claude/.fop-state-*` / `.claude/.fop-active` への Edit/Write は常にブロック。Bash でも `>` / `>>` / `tee` / `sed -i` / `mv` / `cp` / `rm` でこれらのパスに書き込むコマンドはブロック（ただし `fop_state_*` 関数呼び出しは許可）
- **Step 宣言検証（ガード2）**: Bash で `fop_state_(advance|loop|write) <N> ...` を実行する直前に、**Bash コマンド本体（`tool_input.command`）** に、**N が target step と一致する** `【VibeGoGo Step N 開始】` が含まれるかを検証。含まれない場合ブロック。例外: TARGET=2 のときに限り `【VibeGoGo 宣言】`（Step 1 起動宣言）も許容。検証対象を transcript ではなく COMMAND に置く理由: PreToolUse hook 呼び出し時は現メッセージの assistant text が transcript に未書き込みのケースがあり、正規の1回目でも誤判定 → 2回目で「すり抜け」が発生していたため。COMMAND は input に必ず含まれるので transcript タイミングに依存せず確実に検証でき、1回目で必ず通る（auto mode 完走可能）。これにより以下を物理的に防ぐ:
    - Step 開始宣言の省略
    - 宣言番号と advance 番号のズレ（`# 【Step 4 開始】` で `advance 3` 等）
    - 1 つの Bash で複数 advance をチェーン（COMMAND 内に target=N の宣言は 1 つだけ意味を持つため）

  エージェントの書き方の標準形:
  ```bash
  # 【VibeGoGo Step 3 開始】 step=3, phase=investigating, loop=0
  source $HOME/.claude/skills/vibegogo/scripts/fop-state.sh && fop_state_advance 3 investigating
  ```

  注: assistant text 側の宣言テキスト（チャットに人間可読で出すもの）は読み手向けに維持してよいが、hook の検証対象ではない。

**phase 別挙動**:

| phase | 対応 Step | Edit/Write | Bash | Agent | 備考 |
|---|---|---|---|---|---|
| (state file 無し) | 未起動 | 全許可 | 全許可 | 全許可 | VibeGoGo 外の通常作業 |
| `declare` | Step 1 | 全許可（state file 除く） | 全許可（state file 除く） | **ブロック** | 人間のターン |
| `requirements` | Step 2 | 全許可（state file 除く） | `fop_state_(advance\|loop\|write) 3 investigating` 実行直前に `tasks/fop/{id}/requirements.md` の存在を必須化(無ければブロック)。それ以外は全許可（state file 除く） | **ブロック** | Step 0 で握った Goal/Constraints/Acceptance を文書化してから investigating へ |
| `investigating` | Step 3 | `tasks/fop/{id}/` 配下のみ許可、他はブロック | 全許可（state file 除く） | 許可 | 調査メモ書きはエージェント／subagentいずれも可 |
| `planning` | Step 4 | `tasks/fop/{id}/` 配下のみ許可、他はブロック | 全許可（state file 除く） | 許可 | プランニングはエージェント／subagentいずれも可 |
| `task-selected` | Step 5 | **ブロック** | 全許可（state file 除く） | 許可 | Edit/Write はブロック |
| `implementing` | Step 6 | 全許可（state file 除く） | `git\s+commit` / テスト実行コマンド（`swift test`/`npm test`/`pnpm test`/`yarn test`/`pytest`/`go test`/`cargo test`/`jest`/`vitest`/`mocha`/`xcodebuild ... test`）をブロック（**ガード5 対策**） | 許可 | 実装はエージェント／subagentいずれも可 |
| `testing` | Step 7 | 全許可（state file 除く） | `git\s+commit` をブロック。`testing→implementing` 直接遷移（`fop_state_(loop\|advance\|write) <N> implementing`）もブロック（reflection 経由強制）。`fop_state_advance 7 verified` 直前に `.claude/.fop-simplify-sentinel-{fop_id}-{loop_count}` を検証 → 未存在ならブロック（simplify 未起動）、`modified=1` ならブロック（reflection 経由必須） | 許可 | テスト実行 + simplify 起動の物理強制（詳細は末尾「simplify 起動の物理強制」セクション） |
| `reflection` | Step 6-R | `progress.md` のみ許可、他ブロック | reflection→implementing 遷移時は progress.md の mtime 検証 | **許可**（researcher 起動目的） | 冒頭で必ず researcher を再起動して深く深く調査、その結果を引用しながら 4 項目を追記 |
| `verified` | Step 7 末尾 | **ブロック** | 全許可（state file 除く） | 許可 | Step 8 遷移待ち |
| `progress` | Step 8 | `progress.md` と `.fop-target` の `VERSION_FILE_*_PATH` マッチのみ許可、他ブロック | 全許可（state file 除く） | 許可 | Bash 経由の書き込みは state file 以外素通し |
| `commit` | Step 9 | `progress.md` と `.fop-target` の `VERSION_FILE_*_PATH` マッチのみ許可、他ブロック | 全許可（state file 除く、`git\s+commit` ブロックなし） | 許可 | コードロジック変更は禁止（新サイクルの Step 6 で実施）。git add/commit/push 等は Bash で実行可能 |

**設計上の制限**:
- Stop hook は入力 JSON に `cwd` フィールドを前提とする。Claude Code が `cwd` を渡さない仕様変更が発生した場合は Stop hook が素通し（exit 0）になり、「うっかり停止」物理ブロックが機能しない（誤動作はしない、純粋に機能停止のみ）

## エラー認識ルール（hook で物理強制）

Bash 実行で **exit code 非ゼロ / stderr に error,fail,Exception,Traceback,エラー,失敗 / stdout 行頭 error:,fail:** を検出したら、PostToolUse hook が `.claude/.fop-error-pending` フラグを作成。次のツール実行時に PreToolUse hook が現在ターンの assistant text に **「【エラー認識】」** が含まれるかを検証 → 無ければ **exit 2 でブロック**。

エージェントの行動規約:
1. Bash 実行後、結果に異常を見たら **直ちに `【エラー認識】<内容> + 対応方針` テキストをチャットに出力**
2. 対応方針: 修正実行 / リトライ / reflection 経由 / user停止 のいずれかを明示
3. テキスト出力すれば PreToolUse hook がフラグを自動削除、次の実行に進める

**誤検知除外**（hook 側で実装済）:
- `grep` / `rg` / `ag` / `ack` / `find` / `awk` / `sed` / `fgrep` / `egrep` / `jq` / `test` / `[` の exit 1 は「マッチなし」として無視
- `fop_state_*` 関数呼び出しは内部状態管理として除外
- stderr の error 検出は検索系コマンドでは無効化（出力結果の error 文字列を誤検知しないため）

**フラグ復旧**:
- `.claude/.fop-error-pending` を直接 `rm` で削除可（緊急時）
- ただし、直接削除すると認識を飛ばすことになるので原則「【エラー認識】」テキスト経由で解除

## simplify 起動の物理強制（PostToolUse + PreToolUse 連動）

testing phase 中に Skill `simplify` を必ず通すことを hook で物理強制する。エージェントの自己申告ではなく、sentinel ファイル経由で「起動した／修正があった」を検出する。

**sentinel ファイル**:
- パス: `$CWD/.claude/.fop-simplify-sentinel-{fop_id}-{loop_count}`
- 形式: `KEY=VALUE` 多行
  - `started=1`
  - `started_at=<unix-ts>`
  - `modified=0|1`（simplify 起動以降の Edit/Write が走ったら 1）
  - `modified_files=<path1>,<path2>,...`（modified=1 のとき列挙）

**生成・更新・削除のタイミング**:

| トリガ | hook | 挙動 |
|---|---|---|
| testing phase 中に Skill tool で `simplify` 起動を検出 | PostToolUse | sentinel を新規生成（`started=1`, `started_at`, `modified=0`） |
| 同 `loop_count` 中の Edit/Write 成功 | PostToolUse | sentinel の `modified=1` に更新、`modified_files` に追記 |
| `fop_state_advance 7 verified` ガード通過 | PreToolUse（通過後） | sentinel を削除（次サイクルで再要求） |
| `fop_state_loop` で次サイクル開始 | PostToolUse | 旧 `loop_count` の sentinel を削除（新 `loop_count` のものはまだ存在しない） |
| `fop_state_clear` でVibeGoGo 終了 | PostToolUse | sentinel を削除 |

**verified ガード**（PreToolUse、`fop_state_advance 7 verified` 直前）:

```
sentinel が存在しない
  → exit 2「simplify 未起動。testing phase で /simplify を一度通してから verified へ」
sentinel.modified == 1
  → exit 2「simplify が修正を入れた。reflection 経由で再 testing してから verified へ」
sentinel.modified == 0
  → 通過。sentinel を削除して advance 続行
```

**Why**: testing で「動作確認 OK」だけで verified に進むと、simplify 観点（重複・命名・責務分離・効率）の品質ゲートをすり抜ける。さらに simplify が実コードを修正した場合、その修正に対するテストが走っていない状態で verified になる事故が起きる。sentinel + ガード5（既存の testing 中 `git commit` ブロック）+ reflection 経路強制を組み合わせて物理的に閉じる。

**エージェント側の最小行動規約**:
1. testing phase で動作確認が一通り通ったら `/simplify` を起動
2. simplify が修正を入れた場合は reflection に戻り、4 項目記載 → 再 testing → 再 simplify
3. simplify が「修正なし」を返したら `fop_state_advance 7 verified` で抜ける（sentinel は hook が自動削除）
