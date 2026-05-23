# requirements — VibesDeGoGo! hook ロジック欠陥修正

id: 20260519-2040-xlk9 / 起票: 2026-05-19

## Goal

VibesDeGoGo! repo (`skills/vibesdegogo/scripts/`) の hook ロジックに存在する 5 欠陥 + init 汚染掃除を修正し、「Step 順序を物理強制する」という VibesDeGoGo! の設計主張を実体化する。legacy formation workflowsは対象外（ズンジー判断: 今後 VibesDeGoGo! のみ使用）。

修正対象ファイル:
- `skills/vibesdegogo/scripts/vdgg-hook-pretool.sh`
- `skills/vibesdegogo/scripts/vdgg-hook-posttool.sh`
- `skills/vibesdegogo/scripts/vdgg-state.sh`

## Constraints

- 修正は VibesDeGoGo! repo の scripts のみ。legacy formation workflows は一切触らない。
- 正規 happy path（Step 1→9 を正規コマンドで進む）の挙動を変えない。塞ぐのは逸脱経路のみ。
- state file 形式（KEY=VALUE: step/phase/loop_count/current_task/vdgg_id/last_updated）・公開関数シグネチャ（`vdgg_state_*`）は不変。後方互換維持。
- settings.json / hook 登録は修正フェーズでは変更しない（enforcement はregistered legacy hook = 同一ロジックが担う＝ドッグフーディング）。
- 配線張り替え（settings.json: Pre/Post/Stop をlegacy hook to vibesdegogo）は最終 Step の deploy 作業として実施。legacy hook entries削除可否は deploy 時にズンジー確認。
- 軽微3件（guard4 の `cd .claude` 回避 / error認識の transcript タイミング / Stop hook の cwd 依存）は今回スコープ外、別 issue 化。寝かせず方針確定済み。

## Acceptance criteria

1. **A（重大）**: reflection phase で `vdgg_state_(advance|loop|write) <n> verified` 系コマンドを実行すると exit 2 でブロックされる。reflection→implementing 経由は通る。
2. **B（重大）**: reflection phase で progress.md 未更新のまま `vdgg_state_loop 6 implementing` を打つと exit 2。progress.md 更新済みなら通る（番号 5→6 是正、SKILL.md と整合）。
3. **C（重大）**: jq 不在時、`brew install jq` / jq セットアップ系 Bash は通過し、それ以外のツール呼び出しは exit 2 でブロック（フェイルクローズ、かつ install 用 Bash デッドロック無し）。
4. **D（中）**: declare / requirements phase で TASKS_DIR（`tasks/vdgg/{id}/`）配下以外への Edit/Write が exit 2 でブロックされる。
5. **E（中）**: 8→5（progress→task-selected）遷移後、loop_count が 0 にリセットされる。
6. **init掃除**: `vdgg_state_init` 実行時に旧セッション残骸（`.vdgg-error-pending` / `.vdgg-simplify-sentinel-*` / `.vdgg-step-block-*`）が掃除される。
7. 上記 1–6 を、各 hook に擬似 JSON 入力を流す bash 検証スクリプトで再現確認できる（実機不要・テスタブル）。
8. **deploy**: settings.json の PreToolUse/PostToolUse/Stop が vibesdegogo scripts を指す。legacy hook entriesの削除可否はズンジー確認の上で確定。
