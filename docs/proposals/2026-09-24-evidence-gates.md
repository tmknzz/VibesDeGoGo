# VDGG 改善提案: ゲートを「形式」から「証拠」へ（2026-09-24）

調査を飛ばして計画し、そのまま実装する — このサボりを、今の VDGG は機械的に止められない。
Step 3→4 のゲート（`skills/vibesdegogo/scripts/vdgg-hook-pretool.sh` の `investigating|planning` 節、446 行付近）は
`investigation.md` に 7 見出しと非空の本文があるかしか見ておらず、Read/Grep を 1 回も使わずに通過できる。
Step 4→5 は `todo.md` と `progress.md` の存在しか確認しない。
本書は、その穴を塞ぐ 7 項目を実装順の目安つきで記録する。1〜4 は相互依存するため 1 本の VDGG セッションで扱い、6 は独立に回せる。

## 共通の制約

- 変更は Claude Code 版（`skills/vibesdegogo/`）と Codex 版（`.agents/skills/vibesdegogo/`）の両方に入れる。`tests/test-edition-sync.sh` が同期を検査している。
- テストは bash と zsh の両方で回る（#30）。新しいシェルコードは配列の添字や `status` 変数など、両シェルで意味が変わる書き方を避ける。
- Step 3 の見出しを変える場合は `SKILL.md`・`references/subagent_prompts.md`・フックの 3 箇所を同時に直す（`tests/test-investigation-headings-drift.sh`）。

## 1. Step 3 に「読んだ証拠」ゲートを足す

phase が `investigating` の間、PreToolUse フックで Read・Grep・Glob と Bash の読み取りコマンド（`cat`・`sed -n`・`head`・`rg`・`grep` など）が触れたパスを sidecar（例 `.claude/.vdgg-read-{id}`）に追記する。
`vdgg_state_advance 4 planning` の時点で、`## 1. Related files` に列挙されたパスがすべて実在し、かつこの phase 内で読まれていることを要求する。1 件も列挙がなければ止める。

- Bash の読み取りを記録対象に含めないと、`cat` で読んだファイルを「未読」と誤判定して無駄な往復が生じる。
- 重さ: フック側はほぼゼロ。遅くなる分は「今まで読まずに済ませていた分」であり、それが狙い。
- 限界: 読んだうえで浅く理解する、というサボりは止められない。

## 2. Step 4 の計画に「修正箇所の抜粋」を必須にする

`todo.md` の各タスクに次の 3 ブロックを要求する。

1. 修正箇所（`path:line` か関数名）
2. その箇所にある現在のコードの抜粋 — フックが実ファイルと一字一句照合する
3. 何をどう変えるかの意図

修正後のコードは計画では書かせない（理由は 3 を参照）。新規ファイルは「抜粋: 新規」と明記し照合を省く。
抜粋照合は 1 の証拠ゲートを補強する。記憶で書いたコードはまず一致しない。

## 3. Step 6 を「パッチ先行」にする

実装担当（Formation の委譲先を含む）は、まずタスクのパッチファイル（例 `tasks/vdgg/{id}/patch/T1.patch`）を出す。
フックが `git apply --check` を通してから適用し、テストに進む。

- 計画段階で修正後コードを書かせない理由: 計画役（primary や opus）が書くと実質の作者が Claude になり、formation-d の「Codex が書いたコードを別ベンダーの Fable が読む」ベンダー分散が崩れる。委譲の価値もなくなる。
- パッチはタスクごとに実装直前で作るので、先行タスクの変更で文脈行がずれて当たらなくなる問題が起きない（Step 4 で全タスク分を一括生成すると起きる）。
- 機械的な一括変更（多数ファイルのリネーム等）は、パッチの代わりに codemod/sed コマンドとドライランの件数を出させる。
- パッチが大きすぎること自体をタスク分割の合図として扱う（Step 4 の sizing 規則: 4 ファイル以上なら分割）。

## 4. Step 7 で計画と実装を突き合わせる

レビュアーに Step 4 の意図と抜粋、実際の diff を並べて渡し、計画外の変更と計画にあって未実施の変更を指摘させる。
食い違いは止めず、理由を `progress.md` に記録させる。完全一致を強制すると、誤った計画をそのまま実装する方向に圧がかかる。

## 5. 計画のレビュー席を Formation に任意で置く

Step 4 の出力を別ベンダーのモデルに読ませる席（例 `4R`）を追加し、使う Formation でだけ有効にする。
MAGI は使わない。既定が同一モデルの 3 人格で独立性が低く、採点軸も主観的成果物向けのため。
重さ: 外部呼び出し 1 回、セッションあたり数分。

## 6. Formation でモデル・effort・サブエージェントを指定しやすくする

現状の問題（`skills/vibesdegogo/scripts/vdgg-state.sh`）:

- `_vdgg_model_alias`（515 行）のショートハンドが `opus5`/`sonnet5`/`fable5`/`haiku45` で止まっており、`claude-opus-5-5` を指す短縮名がない。利用者は `claude claude-opus-5-5 medium` と書いている。
- `_vdgg_is_effort_token`（540 行）の claude 用 effort が `low|medium|high` のみ。CLI の `--effort` は `xhigh`/`max` も受け付けるが、書くと「モデル名 2 個目」と解釈されて検証エラーになる。
- `_vdgg_parse_seat_value`（560 行）がショートハンドに追加トークンを許さないため、`opus5 medium` のような指定ができない。
- VDGG 内で起動するサブエージェント（Step 6-R のリサーチャー、simplify の観点別エージェント）はモデルも effort も指定しておらず、親セッションを引き継ぐ。
- モデル名の誤記（例 `codex atlus medium`）は preflight を通過し、実行時に初めて落ちる。

提案: 現行モデルのショートハンド追加、ショートハンドへの effort 付与、claude effort に `xhigh|max` 追加、サブエージェント用の席の新設、preflight で codex のモデルカタログ（`~/.codex` の `model_catalog_json`）や claude の既知モデルと照合して未知名を警告。

## 7. 設計原則を SKILL.md 冒頭に明文化する

- 守らせたいことはフックで検査し、散文の指示は判断の手引きにだけ使う（AGENTS.md や SKILL.md の文章は守られない前提で設計する）。
- ゲートは形式ではなく証拠を見る。
- コードを書くのは実装役に限り、計画役は書かない。

## 参考: 同日に確認した周辺事項

- Claude Code の Bash ツールは `$SHELL`（利用者によっては zsh）で動く。`CLAUDE_CODE_SHELL` で bash を指定できる（CLI 実装で確認）。VDGG は zsh 利用者のために両シェル対応を維持する。
- 利用者側の Formation 設定（`~/.config/vdgg/formations/`）はリポジトリ外にあり、本提案の実装では変更しない。
