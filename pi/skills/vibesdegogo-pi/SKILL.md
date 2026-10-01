---
name: vibesdegogo-pi
description: pi上のQwenでVibesDeGoGoのStep 0–9とqwenmagiを実行する。実装・修正・検証タスク用。
---

# VibesDeGoGo! for pi

pi拡張とセットで使う。各LLM呼び出しに現在stateと該当Stepの指示が渡される。
状態・証拠・allowlist・patch・test・reviewの判定は既存VDGG helper/hookが行う。

1回の応答でツールは1件だけ。短い調査、1仮説、小さいpatch、検証の順で進める。
毎Bashで `source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"` してからhelperを呼ぶ。
状態遷移はStep番号とphaseをliteralで書く。ファイル作成と遷移は別tool callにする。
現在phaseの詳細は [Step別指示](references/steps.json) を読む。Codex版SKILL全文は通常不要。
Formationを選んだらStep 0で同名をpreflight/resolveし、`vdgg_state_init --formation <name>`
で保持する。開始前のqwenmagiへも同名の`VDGG_FORMATION`を渡す。各Step開始前に `vdgg_formation_resolve <STEP_KEY>` を解決する。
外部seatは `vdgg_executor_run`、無指定seatは起動中のQwen。失敗をinlineで代演しない。

## qwenmagi

VDGG内の審議は明示的に **qwenmagi** を選ぶ。ロード済みqwenmagiのSKILLと
Formation/AIB保存仕様に従う。Step 0の要件とStep 7の主観的成果物だけを軽量議にかける。
コードの正しさはテストと外部reviewで確認する。
qwenmagi専用Formationがあれば全席その定義を優先。未指定席はprimary（このQwen）。
専用FormationがなくVDGG Formationがある場合、qwenmagiのresolve/runへ同じ
`--vdgg-helper "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"` を渡す。
Formationなしならhelperを渡さず全席primary。`pi model thinking`はVDGGの現行parserに
直接足さず、qwenmagi専用Formationか既存custom executorを使う。
外部席は毎回独立実行し、応答は改変しない。欠席・失敗・不正形式では可決しない。

## 運用

QwenのThinkingや出力上限はprovider側の設定。表示から実効を断定しない。
readやpatchの対象だけを渡し、大きいログ/全repoをcontextへ詰め込まない。
失敗commandの次Bashには `[Error Acknowledged]` と原因/修正方針を書く。
制約変更・破壊操作・未決要件では `[Intentional Stop]` と具体的理由を表示しstateを保持。
完了時は検証結果、残課題、lessons applied/newを報告する。
