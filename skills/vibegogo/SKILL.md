---
name: VibeGoGo
description: "A state-and-hook workflow for Claude Code that keeps coding agents moving until done while stopping only for constraint violations."
version: 1.7.1
---

# VibeGoGo

state file と pre-tool hook で Step 順序を物理強制する直列実行型の自律開発フロー。エージェントが直接実務する設計で、並列性が活きる場面のみsubagentに委任する。

## エージェントの役割

- **宣言してから動く**: 各 Step 開始時に Step 宣言を出力する
- **state file を更新する**: 各 Step 開始/完了で state file 更新
- **エージェント自身が実行 or subagentに委任を選ぶ（Step 3, 4, 6, 7）**: 自分で済むと判断したら自分でやる、規模・並列性・コンテキスト保護の観点で委任が得策なら Agent ツールでsubagentを起動する。判断はエージェントの裁量
- **自分でリードする（Step 1, 2, 5, 8, 9）**: 宣言・要件・タスク選択・進捗・コミット
  - Step 8 は「自分でリード」だが、実機ビルド／実環境確認などの物理作業はuserに依頼する
- **監視・正す**: subagentに委任した場合、方向を見失ったら止めて修正する

**委任判断の目安**:
- **デフォルトはエージェント自身でやる**。委任は限定された場面のみ
- subagentに委任するのは次の 2 ケースだけ:
  1. **並列実行が活きる**: 複数ファイル / 複数モジュールを同時に触る作業を、複数のsubagentに分担させると速い場合
  2. **独立した複数タスク**: 同時に進行できる無関係なタスクが複数あり、エージェントでは直列処理になる場合
- 「コンテキスト節約」「不慣れな領域だから」「長時間かかりそう」は委任の根拠にしない

## いつ使うか

使う: `/VibeGoGo`、「VibeGoGoで」、コード変更フロー（実装・診断・改善）
使わない: 文言のみ、相談タイム

## メンテナンスモード（VibeGoGo 自身の修正に限定）

**VibeGoGo 自身（`skills/vibegogo/` 配下のスクリプト / ドキュメント）を修正するときだけ** 適用する専用モード。VibeGoGo の自己修正に full フロー（深い investigation 再実行・researcher 全起動・simplify 並列3体・deploy 段）を当てると、儀式と実 work の比率が破綻するため抑制する。**VibeGoGo 以外のプロジェクト / コード変更には適用しない**（小さく診断済みでも対象外。従来どおり full フロー）。

なぜ一般化しないか: 「小さい / 軽い」の分量判定は客観計測が難しく、汎用の軽量パスにすると AI 暴走時に hook の物理強制（停止保証）を外す危険がある。対象を VibeGoGo 自身の修正に固定することで、暴走ガードを保ったまま自己修正の儀式過多だけを抑える。一般プロジェクト向けの小変更は、後述の「軽量モード」を使う。**メンテナンスモードと軽量モードは同じものではない**。

メンテナンスモードの規則:
- 変更前に、対象ファイル・目的・変更しない範囲を短く固定する
- 全文再読・全体再設計・広範囲調査を禁止。対象は変更に直接関係するファイルだけに限定
- 調査は `rg` と該当箇所の `Read` のみ（researcher サブエージェント全起動はしない）
- 計画は最大3タスク
- 既存 script / hook / docs の構造を優先し、外部依存追加は禁止
- hook 入出力契約 / state file 形式 / Step 遷移契約を変える場合は full flow に昇格する
- 検証は `bash -n`、`rg` sanity check、必要なら最小 hook simulation のみ。simplify 並列3体は起動せず、小差分は reuse/quality をインラインで確認する
- reflection は、機械的・自明な失敗（タイポ / パス段数誤り等）では researcher 全起動を省略し、根本原因と単一修正を progress に1〜数行で記す
- 検証失敗が2回続く、迷いがある、影響範囲が広がる、または検証不能になった場合は full flow に昇格する
- Step 8 deploy は不要
- 進行確認では止まらない。制約逸脱・破壊的変更・外部依存追加が必要なときだけ確認する
- 完了報告は user 向けの平易な結論を先に出し、必要なら技術メモを後段に分ける

VibeGoGo 以外の通常のコード変更は本モードの対象外。従来どおり full フローに従う。

## 軽量モード（一般プロジェクトの小変更向け）

軽量モードは、一般プロジェクトの小さく閉じた変更にだけ使える短縮フロー。**メンテナンスモードとは別物**で、対象は VibeGoGo 自身に限定されない。ただし AI の自由な軽重判定に任せない。軽量化してよいのは ceremony の量だけで、制約確認・既存パターン確認・検証は省略しない。

### 軽量モードの入口条件

以下をすべて満たす場合だけ使える:

- user が軽量モードを明示する、またはエージェントが軽量モード適用理由を短く提示してから着手する
- 対象ファイル・目的・変更しない範囲が最初に固定できる
- 既存の標準機能・標準コンポーネント・標準API・標準パターンだけで実施できる
- 外部依存追加・独自実装追加が不要
- 検証方法（テスト / ビルド / smoke check / 手動確認）が着手前に明確
- 変更が小さく閉じており、呼び出し元・参照元の確認範囲が限定できる

### 軽量モードで扱ってはいけない対象

次に触れる場合は軽量モード禁止。full flow にする:

- API契約、DB / migration、永続化形式、認証、権限、セキュリティ
- 課金ID、プラン判定、購入 / 決済、Analytics イベント名
- ユーザーデータの削除・移行・不可逆変更
- 法務文言、医療・金融など高リスク説明、利用規約や同意文
- 仕様判断、UX 判断、状態遷移設計、非互換変更
- 依存追加、大規模リネーム、複数モジュール横断変更

### 軽量モードの最小フロー

1. 対象ファイル・目的・変更しない範囲・検証方法を 1〜5 行で宣言する
2. `rg` / Read で、変更箇所と直接の呼び出し元・参照元を確認する
3. 既存パターンに沿って最小差分で修正する
4. 事前に宣言した検証を実行する。検証省略は禁止
5. 結果を「変更内容 / 検証結果 / 残リスク」だけで短く報告する

### full flow への昇格条件

次のいずれかに当たったら、軽量モードを中止して full VibeGoGo に昇格する:

- テスト / ビルド / smoke check が2回失敗した
- 触るファイル、呼び出し元、影響範囲が最初の宣言より広がった
- 仕様判断・互換性判断・データ契約判断が必要になった
- 標準パターンだけでは難しく、独自実装や外部依存が欲しくなった
- 検証方法が不明、または検証できない
- エージェントが「たぶん」「おそらく」で進めそうになった

## 標準優先の基本契約

VibeGoGoでコード変更を扱う場合、Step 0 の Constraints に次の方針を必ず含める。ユーザーが明示的に別方針を指定した場合だけ上書きできる。

- 対象環境の標準機能・標準コンポーネント・標準API・標準パターンを最優先する
- 独自UI、独自コンポーネント、独自状態管理、独自デザインシステム、独自ユーティリティ、外部依存の追加は、必要性が明確でない限り禁止する
- 標準だけで難しい場合は、実装前に「難しい理由」「代替案」「影響範囲」「後で標準へ戻せるか」を報告し、userの確認を取る
- 勝手に独自実装や外部依存で突破しない

既存の独自実装を見つけた場合は、Step 3 の investigation.md に「標準で置き換え可能か」「置き換えない場合の理由」を記録する。Step 7 の検証では、標準から逸脱した箇所が残っていないかを確認し、残る場合はファイル名・理由・代替不能な根拠を progress.md に明記する。

## state file 構造（概要）

各VibeGoGoセッションは一意のID（`YYYYMMDD-HHMM-xxxx`）で管理される。state file と tasks ディレクトリは ID ごとに分離される。

```
.claude/.fop-active              ← 現在アクティブなVibeGoGoのID
.claude/.fop-state-{id}          ← IDに対応するstate file
tasks/fop/{id}/todo.md           ← IDごとのタスク管理
tasks/fop/{id}/progress.md
tasks/fop/{id}/investigation.md  ← Step 3 で生成される深い調査レポート
```

state file は KEY=VALUE 形式（`step` / `phase` / `loop_count` / `current_task` / `fop_id` / `last_updated`）。

詳細: `references/state_helpers.md`（state file 全フィールド・ヘルパー関数 `fop_state_*` リファレンス・連続性チェック・自律制限）

## phase 一覧

| phase | 対応 Step | 概要 |
|---|---|---|
| `declare` | Step 1 | フォーメーション宣言 |
| `requirements` | Step 2 | 要件文書化 |
| `investigating` | Step 3 | 深い調査 |
| `planning` | Step 4 | プランニング |
| `task-selected` | Step 5 | タスク選択 |
| `implementing` | Step 6 | 実装 & テスト作成 |
| `testing` | Step 7 | 自己検証ループ |
| `reflection` | Step 6-R | 振り返り（researcher 再起動） |
| `verified` | Step 7 末尾 | 検証完了 |
| `progress` | Step 8 | 進捗更新・検証依頼 |
| `commit` | Step 9 | コミット |

## Step 宣言フォーマット

宣言は **2 種類**:

- **Step 1（フォーメーション起動時の宣言）**: Step 0 で握った要件と全体方針と ID を提示（`【VibeGoGo 宣言】 id=...` 形式）
- **Step 2 以降（各 Step 開始時の進捗宣言）**: 1 行で現在地を示す
  ```
  【VibeGoGo Step N 開始】 step=N, phase=PHASE_NAME, loop=LOOP_COUNT
  ```

詳細: `references/output_formats.md`（Step 0 / Step 1 宣言テンプレ・各種出力フォーマット集）

## Step 順序 概観

### Phase 0: 要件握り（Step 0、state file 未生成プロトコル）

#### Step 0: 要件握り（エージェント + user対話）

**目的**: フォーメーション起動の前提条件として、userと以下3項目を必ず握る。

1. **Goal**: 何を達成したいか（成果物・状態・ユーザー価値）
2. **Constraints**: 守るべき制約（既存仕様・互換性・パフォーマンス・スコープ外）
3. **Acceptance criteria**: 完了の判定基準（具体的な確認項目、テスタブルが望ましい）

**やり方**:
- userの依頼を聞いた段階で、エージェントが上記3項目をドラフトしてチャットに提示
- 不明点や曖昧さはこの段階でuserに質問する（Step 1 以降に持ち込まない）
- userから明示的な OK が出たら Step 1 へ進む（init する）

**この Step は state file が未生成のため hook で物理強制できない**。エージェントの誠実さでプロトコルを守る。

詳細（出力テンプレ・ルール）: `references/output_formats.md`

### Phase 1: 土台作り（Step 1-4）

#### Step 1: フォーメーション宣言（エージェント）

```bash
source $HOME/.claude/skills/vibegogo/scripts/fop-state.sh
fop_state_init
```

`fop_state_init` が step=1, phase=declare, loop_count=0 で state file を初期化するので、**続けて `fop_state_write` を呼ぶ必要はない**。

##### feature ブランチ生成（branch-pr ワークフロー、デフォルト）

`fop_state_init` の直後、**コード編集（Step 6）より前に** 作業ブランチを用意する。`.fop-target` の `WORKFLOW`（未設定時 `branch-pr`）/ `BASE_BRANCH` を読む。詳細スキーマ: `references/target_schema.md`

```bash
WORKFLOW=branch-pr; BASE_BRANCH=""
if [ -f "$(pwd)/.fop-target" ]; then source "$(pwd)/.fop-target"; fi
if [ "${WORKFLOW:-branch-pr}" != "trunk" ]; then
    if [ -z "${BASE_BRANCH:-}" ]; then
        BASE_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
        BASE_BRANCH=${BASE_BRANCH:-main}
    fi
    CUR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    case "$CUR" in
        vibegogo/*) : ;;  # 既に作業ブランチ上 — そのまま使う（入れ子にしない）
        *) git checkout -b "vibegogo/$(fop_get_id)" ;;
    esac
fi
```

`WORKFLOW=trunk` のプロジェクトはこのブロックをスキップし、現ブランチで進む（旧挙動）。branch-pr では以降の base ブランチ直コミット / 直 push を hook がブロックする。

続けて Step 1 宣言フォーマットを出力（id 部分は `$(fop_get_id)` の結果で埋める）。詳細: `references/output_formats.md`

#### Step 2: 要件文書化（エージェント）

Step 0 で握った3項目を **`tasks/fop/{id}/requirements.md` に書き出す**。Step 1 宣言で口頭提示した内容を、後続 Step で参照できる正本として固定する役割。

必須見出し（順序固定、すべて埋める）は `## Goal` / `## Constraints` / `## Acceptance criteria` の 3 つ。詳細: `references/output_formats.md`

書き出した後、Step 3 (investigating) に進む前に **hook が `requirements.md` の存在を必須化** する（無いとブロック）。

```bash
fop_state_advance 2 requirements
```

#### Step 3: 深い調査（エージェント or subagent）

要件に関する **既存コードの深い調査** を実施し、`tasks/fop/{id}/investigation.md` に生成する。**Step 4 のプランナーはこのレポートを入力にする**。

**実行者の選択**: デフォルトはエージェント自身。並列実行で得する場合のみsubagentに委任。

**「深い」を担保する原則:**
- 推測で書かない。実コードを `Read` / `Grep` / `Glob` で読み込む
- 単一ファイルで終わらせない。**呼び出し側まで辿る**（影響範囲確定のため）
- 過去の git log / lessons / journal も視野に入れる
- 「不確か」「未調査」と自覚した部分はそう明記する

```bash
fop_state_advance 3 investigating
```

サブエージェント型: `Explore`（thoroughness="very thorough"）

investigation.md の必須見出し7項目: 詳細 `references/output_formats.md`
subagentプロンプトテンプレ: 詳細 `references/subagent_prompts.md`

#### Step 4: プランニング（エージェント or subagent）

`investigation.md` を入力に、変更規模を見積もり、タスク粒度を決めて `tasks/fop/{id}/todo.md` と `tasks/fop/{id}/progress.md` を生成する。

**実行者の選択**: デフォルトはエージェント自身（プランニングは並列化に向かない）。互いに独立した複数領域を別々に計画する場合のみ委任。

**タスク粒度の判断基準:**
- 対象メソッド1-2個、ファイル1-3個 → タスク1つにまとめる
- 対象ファイル4+、独立した変更が複数 → 分割する
- 「1回の実装サイクルでまとめてやれるか？」が基準

```bash
fop_state_advance 4 planning
```

サブエージェント型: `general-purpose`（opus）

todo.md / progress.md の書式とsubagentプロンプトテンプレ: 詳細 `references/subagent_prompts.md`

#### Step 5: タスク着手（エージェント）

`tasks/fop/{id}/todo.md` から次のタスクを1つ選択し、state file の `current_task` に記録する。

```bash
fop_state_advance 5 task-selected
fop_state_write 5 task-selected <loop_count> "T1: タイトル"  # current_task を埋める
```

`fop_state_advance` は current_task を維持するだけで新規記録しないため、**選択後に `fop_state_write` を1回呼んで current_task を埋める**。

### Phase 2: 実装サイクル（Step 6-7）

#### Step 6: 実装 & テスト作成（エージェント or subagent）

コードとテストを書く。

**実行者の選択**: デフォルトはエージェント自身（current_task は1タスクなので普通は逐次実装で完結）。互いに独立した複数ファイルを並列で実装できる場合のみ委任。

```bash
fop_state_advance 6 implementing
```

サブエージェント型（委任時）: `general-purpose`（opus）。プロンプトテンプレ: 詳細 `references/subagent_prompts.md`

#### Step 7: 自己検証ループ（エージェント or subagent）

テスト実行 → 失敗なら修正 → 再テスト。全パスするまでループ。
テストが書けないプロジェクト（SwiftUI 等）では、ビルド確認 + シミュレータ or 実機での動作確認を行う。

**実行者の選択**: デフォルトはエージェント自身（テスト→修正ループは状態を握ったまま回せる方が良い）。

**検証前の確認ポイント言語化（実行者が実施）**: 何を確認するかを 1〜3 項目の箇条書きにしてから実行する。

**テスト通過後の simplify レビュー（必須、hook で物理強制）**: テスト全パス後、`verified` に進む前に **`simplify` スキルを起動** して変更コードのレビュー（reuse / quality / efficiency）を実施する。起動の有無と修正の有無は **sentinel ファイル `.claude/.fop-simplify-sentinel-{fop_id}-{loop_count}` を hook が検証** する（PostToolUse hook が simplify Skill 起動と Edit/Write を sentinel に記録、PreToolUse hook が `fop_state_advance 7 verified` 直前に sentinel を読む）。

**simplify の判定（hook 挙動と一致）**:
- **未起動**（sentinel 不在）→ `fop_state_advance 7 verified` を打つと hook が exit 2 で「simplify 未起動」をブロック。simplify を起動してから再度 advance すること
- **修正なし**（sentinel に `modified=0`、または simplify が「問題なし」と判断）→ `fop_state_advance 7 verified` で進む（hook 通過）
- **simplify が修正を入れた**（sentinel に `modified=1`、Edit/Write を実行した）→ コードが変わったので **必ず再テスト**。`fop_state_advance 7 verified` を打っても hook が exit 2 で「simplify が修正を入れたため verified 直接遷移は禁止」をブロックする。`fop_state_advance 6 reflection` 経由で `implementing` に戻り、reflection で「simplify 由来の修正内容と再テストの仮説」を progress.md に追記して `fop_state_loop 6 implementing` → 再 testing

**simplify の修正範囲は current_task のスコープ内に留める**。スコープを超えそうな修正は採用せず、別タスクとして todo.md に追加する判断もアリ。

**重箱の隅は突かない**。simplify が指摘する軽微な懸念は通す。reflection に戻すべきは「これは直さないと本番で困る」レベルの修正だけ。ただし simplify が **Edit/Write を実行した時点で hook が `modified=1` を立てる** ため、軽微な修正であっても sentinel が `modified=1` であれば reflection 経由が物理強制される（妥協案: testing 中 simplify 起動後の Edit/Write は全て modified=1 扱い）。

**ループ上限**: `loop_count` が **99 に達したら** 一度ループを止め、state を `implementing` のまま維持してエージェントに戻す（暴走時の安全弁）。

```bash
fop_state_advance 7 testing
```

テスト全パス後:
```bash
fop_state_advance 7 verified
```

**テスト失敗時は必ず reflection を経由する**:
```bash
fop_state_advance 6 reflection  # testing → reflection（loop_count 維持）
```

#### Step 6-R: 振り返り（reflection phase、subagent）

##### 0. 冒頭で必ず深い調査（researcher 再起動）

reflection に入った最初の作業は **researcher サブエージェントを再起動して該当タスクの根本原因を深く深く調査** すること。これを飛ばして 4 項目を書き始めるのは禁止（推測ベースの行き当たりばったり修正でゴミコードが増える）。

- 投げる: `Agent(subagent_type="Explore", thoroughness="very thorough", prompt=researcher 失敗深掘りモード)`
- researcher への入力（必須）: 失敗ログ or simplify 指摘（全文） / 該当タスクの bite-sized 詳細 / 過去の試行回数 (`loop_count`) / 既存 `investigation.md` パス / 過去の retry 履歴 `investigation-r{0,1,...}.md`（あれば全部）
- researcher の成果物: `tasks/fop/{id}/investigation-r{loop_count}.md`（必須見出し 7 項目、詳細 `references/output_formats.md`）
- researcher への制約: 推測禁止 / 呼び出し側まで辿る / git log（直近 10 件）/ lessons / journal も視野 / 過去の retry 履歴を全部 Read してから書く / 「軽く見て終わり」禁止

researcher の調査結果が揃ってから、エージェントが下記 4 項目を progress.md に追記する。

##### reflection 中の制限（hook で物理強制）

- Edit/Write は **`progress.md` と researcher の retry 調査書 `tasks/fop/{id}/investigation-r{loop_count}.md` のみ許可**（コード編集禁止）。researcher が §0 で investigation-r{loop}.md を書けるようにするための例外
- Agent（subagent呼び出し）は **researcher 起動目的で許可**
- Read/Grep/Bash で追加調査するのも自由

##### 4 項目を progress.md に追記（Systematic Debugging 準拠）

1. **Root Cause Investigation（失敗要因）**
2. **Pattern Analysis（動作リファレンスとの差異）**
3. **Hypothesis（単一仮説）**
4. **Implementation 計画（単一修正）**

詳細（各項目の必須要素）: `references/output_formats.md`

**reflection 中の禁止事項（量的・質的ガード）:**
- §0 の researcher 起動を省略してエージェント自身の調査だけで済ませる
- Pattern Analysis を「重要でないだろう」で飛ばす
- 複数の修正仮説を同時に implementing で試す
- 症状への対症療法（根本原因を見ずに patch 当て）
- `loop_count > 3` になっても reflection で「アーキテクチャレベルで何かおかしい可能性」に触れない（**3 回以上失敗したらアーキテクチャ検討を progress.md に明記必須**）

追記完了後に implementing へ戻す:
```bash
fop_state_loop 6 implementing  # reflection → implementing（loop_count +1）
```

hook は reflection → implementing 遷移時に **progress.md の mtime が state file 突入時より新しいか** を検証する。更新していない場合はブロック。

**verified 到達後は、エージェントが続けて Step 8 を開始する**:
```bash
fop_state_advance 8 progress
```

サブエージェント型: `general-purpose`（sonnet）

### Phase 3: 完了（Step 8-9）

#### Step 8: 進捗更新・検証依頼（エージェント）

```bash
fop_state_advance 8 progress
```

Step 8 の具体的な手順は **プロジェクトルートの `.fop-target`**（VibeGoGo ターゲット設定ファイル）で決まる。設定ファイルが無いプロジェクトではバージョン更新をスキップし、検証依頼のみ行う。

`.fop-target` のスキーマと例: 詳細 `references/target_schema.md`

##### 手順

1. **`.fop-target` 読み込み**:
   ```bash
   if [ -f "$(pwd)/.fop-target" ]; then
       source "$(pwd)/.fop-target"
   fi
   ```

2. **バージョン更新**（`VERSION_FILE_*_PATH` が設定されている場合のみ）:
   - 各 `VERSION_FILE_N_PATH` のファイルの `VERSION_FILE_N_KEY` を更新
   - 新しい値は `VERSION_FORMAT` / `VERSION_EXAMPLE` を参考に生成
   - **必ず最新コミットより新しい値にする**（`git show HEAD:<path> | grep <key>` で現状確認）
   - `.fop-target` が無い場合はこのステップ全体をスキップ

3. **検証依頼（エージェント主導でuserに投げる）**: `DEPLOY_COMMAND` / `DEPLOY_TARGET` に従いuserに依頼
   - `.fop-target` が無い or `DEPLOY_COMMAND` 未設定なら、userに「どう検証する？」と確認

4. **ビルド/install 完了後、ビルドナンバーを出力（必須）**: 詳細 `references/output_formats.md`

5. **確認ポイント言語化（エージェントが実施）**: `VERIFY_TYPE` に沿った **具体的な確認内容** をuserに提示する（例：「○○画面で△△ボタンを押して、□□が表示されることを確認して」）

6. `tasks/fop/{id}/progress.md` を更新。全タスク完了かチェック（全セクションが「状態: 完了」か）

- 未完了タスクあり → Step 5 に戻る: `fop_state_advance 5 task-selected`
- 全タスク完了 → Step 9 へ

#### Step 9: コミット（エージェント）

```bash
fop_state_advance 9 commit
```

Step 8 でバージョン番号を更新した場合、そのファイルもコミット対象に含める。コミットは現在の **feature ブランチ**（Step 1 で切った `vibegogo/{id}`）上で行う。

コミット完了後、`.fop-target` の `WORKFLOW`（未設定時 `branch-pr`）で分岐する:

```bash
WORKFLOW=branch-pr; BASE_BRANCH=""
if [ -f "$(pwd)/.fop-target" ]; then source "$(pwd)/.fop-target"; fi
```

##### branch-pr（デフォルト）

feature ブランチを push し、PR を作成して **停止する**。マージはしない。

```bash
if [ -z "${BASE_BRANCH:-}" ]; then
    BASE_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
    BASE_BRANCH=${BASE_BRANCH:-main}
fi
BR=$(git rev-parse --abbrev-ref HEAD)
git push -u origin "$BR"
gh pr create --base "$BASE_BRANCH" --head "$BR" \
    --title "<コミット要約と同趣旨>" \
    --body "<Goal / 変更概要 / 検証結果（ハーネス・ビルド等）/ 残リスク>"
```

PR URL を完了報告に必ず含める。**ここで停止**し、マージ可否は人の判断に委ねる。

> マージ作業はエージェント委任。**人が承認したら** エージェントが次を実行する（GREEN だけでの自動マージは禁止）:
> ```bash
> gh pr merge --squash --delete-branch
> git checkout "$BASE_BRANCH" && git pull --ff-only
> ```
> 承認前にこれを先回り実行してはならない（制約逸脱）。

##### trunk（`.fop-target` で `WORKFLOW=trunk` を明示した場合のみ）

旧挙動。現ブランチへ直接コミットし、`AUTO_PUSH=true` のときだけ push する:
```bash
if [ "${AUTO_PUSH:-false}" = "true" ]; then git push; fi
```
push しなかった場合は、user 向け本文では「GitHub にはまだ反映していません」と平易に書き、技術メモで「push 未実行（AUTO_PUSH 未設定/false）」を明記する。

##### 共通: state クリアと締めくくり

PR 作成（branch-pr）/ commit・push 判断（trunk）まで終えたら state をクリアする。branch-pr ではフォーメーションサイクルはここで完了扱い（マージは承認後の後続アクション）:
```bash
fop_state_clear
```

**フォーメーション完了の締めくくり（必須）**: `fop_state_clear` 後、user 向けに「何が終わったか / 次に何が必要か」を平易に出し、最終ビルドナンバー（および branch-pr では PR URL）をチャットに明示出力する。技術詳細は後段の「技術メモ」に分ける。フォーマット詳細: `references/output_formats.md`

## コミット規約

`{変更種別}: {要約}`

- 変更種別: `feat` / `fix` / `refactor` / `docs` / `test` / `chore`
- 要約は 50 字以内を目安
- 本文に `Co-Authored-By:` を付ける（グローバル指示に従う）

詳細: `references/output_formats.md`

## pre-tool hook ルール（概要）

実装側の挙動の概要:

- **state file 保護（ガード4）**: `.claude/.fop-state-*` / `.claude/.fop-active` への書き込みは常にブロック（`fop_state_*` 関数経由のみ許可）
- **Step 宣言検証（ガード2）**: `fop_state_(advance|loop|write) <N> ...` 実行直前に Bash コマンド本体に `【VibeGoGo Step N 開始】` が含まれるかを検証
- **phase 別 Edit/Write/Bash/Agent 許可**: phase ごとに何が許可・ブロックされるかが決まる
- **エラー認識ルール**: Bash 実行で異常検出 → 次のツール実行前に `【エラー認識】` テキストを必須化

詳細（phase 別挙動の表、エラー認識ルール詳細、設計上の制限）: `references/hook_rules.md`

## サイクル完了後の自律継続

`fop_state_clear` 直後（VibeGoGo 完走時）、**次の作業が明確に存在する** 場合は、エージェントの自律判断で **次のサイクルを停止せず即起動する**（userの追加承認を待たない）。

「次の作業が明確」の判定基準（いずれか満たせば自律継続）:
1. **userから事前に複数タスクが列挙されていて未消化のものがある**（例: 「A, B, C をやって」と指示済み、今回 A 完了 → B が次に控える）
2. **進行中の大きな目標の中で次の一歩が自明**（例: ライブラリ全体を Swift 化中で、今ファイルが終わったら次のファイルに進むのが自明）
3. **完了報告に対してuserが事前に「次は X」と明示済み**

判定が曖昧 / 該当なしの場合: userに完了報告して指示待ち（停止）。

次のサイクルで使うフォーメーションは、文脈に応じてエージェントが選ぶ（同じVibeGoGo でも、フォK / フォM でも可）。**サイクル間の確認質問はしない、完走優先**。

## 途中止まらないためのガード（ベスプラ集約）

サイクル中に「気づかぬうちに停止」「迷って先に進めない」を防ぐ。VibeGoGo はエージェントが直接実務するから、エージェントが手を止めると即サイクル停止になる。

### 1. silent stop 禁止
何らかの理由で進めなくなったら **黙って止まらず必ず明示**:
- progress.md に「停止理由: <具体的な原因>」を追記
- エージェント発のテキストで「停止しました、理由は X」を明示出力（userが気づける形）

### 2. ambiguity loop 禁止（迷ったら決める）
判断材料が揃わずに「どっちでも良いか」と迷い続けるのを禁止:
- 既定値を持つ（仕様未定なら直前 retry の仕様維持、新規なら最も保守的な選択）
- 仕様判断が必要な箇所は requirements.md / investigation.md に書き出してから進む
- 不確かなら明示停止 → user指示待ち。**「とりあえず進める」と「明示停止」のどちらかで、中間の沈黙はない**

### 3. cost / step guard
- `loop_count >= 99` で hook が物理ブロック（既設）
- 同タスクで `loop_count > 3` ならアーキテクチャ検討を progress.md に明記必須（reflection で物理強制）
- ループが収束しないなら明示停止 → user指示待ち

### 4. context overflow 予兆対策
エージェントが直接実務するからコード読み込みで context 圧迫が早い。25% 切り目安で:
- `tasks/fop/{id}/session-summary.md` を生成（実装方針・残タスク・次セッションへの引き継ぎ）
- userに「コンテキスト圧迫、新セッション推奨」を明示

### 5. 進行確認は禁止、制約逸脱確認は必須
「これで進めて良いですか？」「次に進んで良いですか？」のような進行確認で停止しない。判断は Step 0 で握った Goal / Constraints / Acceptance criteria と既存実装パターンに従い、自律的に実装・検証・進捗更新まで進める。

ただし、次に該当する場合は実装前確認を必須とする:
- Step 0 / requirements.md の Constraints から逸脱する
- 対象環境の標準機能・標準コンポーネント・標準API・標準パターンでは実現できず、独自実装が必要になる
- 外部依存を追加・変更する
- 既存仕様、永続化形式、API契約、課金ID、Analyticsイベント名、ユーザーデータ、認証、権限、セキュリティに影響する
- データ削除、不可逆変更、大規模リネーム、履歴破壊などの破壊的操作を行う
- Acceptance criteria を満たせない、または検証不能である

確認が必要な場合は、長い相談にせず「抵触する制約」「標準/既存方針だけでは難しい理由」「推奨案」「代替案」「影響範囲」を短く提示して停止する。迷いがあるだけ、選択肢が複数あるだけ、軽微な実装差があるだけでは停止理由にしない。

### 6. 失敗の明示報告（黙って次に行かない）
testing 失敗 / simplify 修正必要を出した場合は **必ず reflection 経由**（hook で物理強制）。失敗系は二系統あり、いずれも hook が物理強制する:
- **testing 失敗系**: testing → implementing 直接遷移は hook がブロック。`fop_state_advance 6 reflection` を経由するしかない
- **simplify 修正必要系**: simplify が Edit/Write を実行すると PostToolUse hook が sentinel `.fop-simplify-sentinel-{fop_id}-{loop_count}` に `modified=1` を記録。直後の `fop_state_advance 7 verified` を PreToolUse hook が exit 2 でブロックし、reflection 経由を案内する

reflection の冒頭で researcher 再起動 → 4 項目を progress.md に記載。失敗を内部で握って次の implementing に進むのは禁止。

### 7. 「軽い修正だから」で reflection 飛ばし禁止（VibeGoGo 固有）
エージェントが「ちょっと直すだけだから」と reflection を経由せず implementing に直接戻るのは禁止（hook で物理強制済）。**毎回 reflection、毎回 researcher 起動**で深く調べる。simplify が Edit/Write を出した時点で sentinel に `modified=1` が刻まれ、verified 直接遷移は exit 2 でブロックされる（軽微・重大の判断は hook がしない、Edit/Write の有無だけが判定基準）。

### 8. 「自分で調査すれば速い」で researcher 省略禁止
reflection の researcher 起動はサボりが出やすい。「エージェントが Read/Grep で見れば 30 秒」と思っても起動する（深さが足りないと同じ失敗を繰り返す）

## セットアップ

新環境導入時の手順（依存コマンド `jq` / `~/.claude/settings.json` への hook 登録 / プロジェクト側 `.fop-target` 作成）: 詳細 `references/setup.md`

## チェックリスト

各 Step 完了時にチェック:

- [ ] Step 0: userと Goal / Constraints / Acceptance criteria を握る（state file 未生成、対話のみ）
- [ ] Step 1: `fop_state_init` 実行 → Step 1 形式の宣言出力（Step 0 の3項目を埋め込む）
- [ ] Step 2: `tasks/fop/{id}/requirements.md` に必須見出し3項目（## Goal / ## Constraints / ## Acceptance criteria）で文書化 → `fop_state_advance 2 requirements`
- [ ] Step 3: エージェント or subagentで `investigation.md` 生成（必須見出し7項目すべて埋める）→ `fop_state_advance 3 investigating`
- [ ] Step 4: エージェント or subagentで todo.md / progress.md 生成（investigation.md を Read）→ `fop_state_advance 4 planning`
- [ ] Step 5: タスク1つ選択 → `fop_state_write 5 task-selected` で current_task 埋め
- [ ] Step 6: エージェント or subagentでコード/テスト → `fop_state_advance 6 implementing`
- [ ] Step 7: エージェント or subagentでテスト or 実機確認 → 全パス後 **simplify レビュー** 実施（**`fop_state_advance 7 verified` 直前に simplify 起動済み — hook が sentinel `.fop-simplify-sentinel-{fop_id}-{loop_count}` を検証、未起動 / `modified=1` はブロック**）→ 修正なし or 軽微なら `fop_state_advance 7 verified`（loop_count<99 が条件）、修正ありなら **reflection 経由（冒頭で必ず researcher 再起動 → investigation-r{loop_count}.md 生成 → 4 項目 progress.md 追記）→ implementing → 再テスト**
- [ ] Step 8: `.fop-target` 参照でバージョン更新 → 検証依頼 → **ビルド/install 完了後にビルドナンバー出力（YYYYMMDD+ABC 形式）** → 確認ポイント言語化 → progress.md 更新 → `fop_state_advance 8 progress`
- [ ] Step 9: コミット → `.fop-target` の `AUTO_PUSH=true` の場合のみ push（未設定なら user 向け本文と技術メモで未反映を明記）→ `fop_state_clear` → **平易な完了報告 + 技術メモ + 最終ビルドナンバー出力**
