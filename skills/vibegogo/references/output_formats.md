# [VibeGoGo 参照: 出力フォーマット集]

このファイルは SKILL.md 本体から切り出された詳細補足。Step 0、Step 1、Step宣言、Step 6-R reflection、Step 8（ビルドナンバー）、Step 9（完了宣言）の出力テンプレートを集約する。

## Step 0: 要件握り 出力フォーマット（毎回必須、簡潔・項番つき）

```markdown
## 【VibeGoGo Step 0】要件握り

- **Goal**:
  1. <達成したいこと（短く）>
- **Constraints**:
  1. <守るべき制約（短く）>
- **Acceptance criteria**:
  1. <完了の判定基準（短く、テスタブル）>
```

ルール:
1. **3点セット必須**: Goal / Constraints / Acceptance criteria を必ず全部出す（1つでも欠けたら NG）
2. **項番つき**: 各項目内の要素は `1.` `2.` ... と項番をつける（要素が1つでも `1.` をつけて統一感）
3. **簡潔**: 1要素は1行〜数行、長文の説明は書かない（書きたくなったら investigation.md / requirements.md に回す）
4. **Goal に手段を混ぜない**: 「○○を SKILL.md に書く」「○○を組み込む」は手段＝Acceptance criteria 側。Goal は到達したい状態（why / what）を書く
5. **標準優先制約を入れる**: コード変更では、Constraints に「対象環境の標準機能・標準コンポーネント・標準API・標準パターンを最優先。独自UI/独自コンポーネント/独自状態管理/独自デザインシステム/独自ユーティリティ/外部依存の追加は禁止。標準だけで難しい場合は実装前に理由・代替案・影響範囲を報告して確認を取る」を含める
6. **逸脱チェックを完了条件に入れる**: Acceptance criteria に「標準から逸脱した箇所がないこと。残る場合はファイル名・理由・代替不能な根拠が明記されていること」を含める

## Step 1: フォーメーション宣言フォーマット

Step 0 で握った要件と、VibeGoGo の全体方針と ID を提示する。

```
【VibeGoGo 宣言】 id=<fop_get_id の出力>

## 要件（Step 0 でuserと握った内容）
- Goal: <達成したいこと>
- Constraints: <守るべき制約>
- Acceptance criteria: <完了の判定基準>

## 進行方針
・Step 0（要件握り）はuserとの対話で完了済み（この宣言の前段）
・Step 1（この宣言）と Step 2（要件文書化）をわたし（エージェント）が実行する
・Step 3（深い調査）と Step 4（計画）と Step 6/7（実装/検証）は基本エージェントが直接実行。並列実行が活きる場面（複数ファイル並行 / 独立した複数タスク同時進行）のみsubagentに委任
・Step 5（タスク選択）はエージェント自身が行う
・state file（.claude/.fop-state-{id}）で phase 進捗を管理、hooks で順序強制
・tasks は tasks/fop/{id}/ に格納
・Step 8（進捗更新・検証依頼）と Step 9（コミット）はエージェントが主導
```

## Step 2 以降: 各 Step 開始時の進捗宣言（1 行）

```
【VibeGoGo Step N 開始】 step=N, phase=PHASE_NAME, loop=LOOP_COUNT
```

## Step 2: requirements.md の必須見出し（順序固定、すべて埋める）

```markdown
## Goal
<達成したいこと>

## Constraints
<守るべき制約>

## Acceptance criteria
<完了の判定基準>
```

## Step 3: investigation.md の必須見出し（順序固定、すべて埋める）

1. `## 1. 関連ファイル一覧` — パス + 役割の対応表
2. `## 2. 既存実装パターン` — どんな書き方で実装されているか（命名・構造）
3. `## 3. 影響範囲` — 呼び出し側 / 依存先 / データフロー
4. `## 4. 過去の類似実装` — git log / lessons から見つけた類似ケース、教訓
5. `## 5. 想定される副作用 / リスク` — テスト・パフォーマンス・互換性
6. `## 6. 制約条件` — 命名規約 / フレームワーク制約 / プロジェクト固有のルール
7. `## 7. テスト戦略` — 何をどう検証するか（テスト書ける場合）/ 実機確認ポイント（書けない場合）

## Step 6-R: reflection 4 項目（progress.md に追記、Systematic Debugging 準拠）

**前提**: §0 で researcher が生成した `investigation-r{loop_count}.md` を **必ず Read** してから書く。

1. **Root Cause Investigation（失敗要因）**: 戻り理由の根本原因。`investigation-r{loop_count}.md` §3「影響範囲」§4「過去の類似実装」を引用しながら原因を特定。テスト/ビルド失敗ならログの該当行も引用、品質問題（Step 7 の simplify レビュー起因）なら simplify が指摘した観点と該当箇所のコードを引用。推測で書かない

2. **Pattern Analysis（動作リファレンスとの差異）**: 動作している類似コード / リファレンス実装（`investigation-r{loop_count}.md` §2/§4 を参照）と比較し、何が違うかを箇条書きで列挙。「これは重要でないだろう」で飛ばさない。前ループで何を変えたか（simplify 由来なら simplify が入れた修正内容）も含める

3. **Hypothesis（単一仮説）**: 「X が原因だと考える理由は Y」形式で **単一仮説** を明記。複数仮説の同時検証は禁止。仮説が立たないなら「不確か」と明言してエージェントに戻す

4. **Implementation 計画（単一修正）**: 次の implementing で何をどう変えるか。**単一の修正のみ**。「ついでに」改善・症状への対症療法（根本原因を見ずに patch 当て）は禁止。simplify 修正をそのまま採用するなら「simplify 修正済み、再テストで検証」と明記

## Step 8: ビルドナンバー出力（deploy 完了後、必須）

deploy 完了後、新しいビルドナンバーを `VERSION_FORMAT` に従った形式（TimeCamera- 等は `YYYYMMDD+連番アルファベット`、例: `20260426A`）で **チャットに明示出力する**。userが実機検証時にどのビルドが対象か即座に判別できるようにする。

- 取得元: `.fop-target` の `VERSION_FILE_*_PATH` で指定された各ファイルの `VERSION_FILE_*_KEY` 値
- 複数 VERSION_FILE がある場合は全部出力
- 例:

```
【ビルドナンバー】
- project.yml CURRENT_PROJECT_VERSION: 20260426A
- AnalyticsService.swift buildVersion: 20260426A
```

## Step 9: 完了宣言フォーマット（fop_state_clear 後、必須）

最終ビルドナンバーを `VERSION_FORMAT` に従った形式でチャットに明示出力する。サイクルで何を commit したか、push したかをuserが視認できるようにする。

```
【VibeGoGo 完了】 id=<fop_id>
ビルドナンバー:
- project.yml CURRENT_PROJECT_VERSION: 20260426A
- AnalyticsService.swift buildVersion: 20260426A
Push:
- 実行済み / 未実行（AUTO_PUSH 未設定 or false）
```

`.fop-target` が無い or `VERSION_FILE_*` 未設定なら「（バージョンファイル無し）」と明記して締める。

## コミットメッセージ規約

`{変更種別}: {要約}`

- 変更種別の語彙: `feat`（新機能）/ `fix`（バグ修正）/ `refactor`（挙動変えない整理）/ `docs`（文書）/ `test`（テスト）/ `chore`（その他）
- 要約は 50 字以内を目安
- 本文は必要に応じて `Co-Authored-By:` を付ける（グローバル指示に従う）
