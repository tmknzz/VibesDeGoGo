# VibesDeGoGo! for pi / Qwen

piの拡張でCodex版state/evidence/hooksを再利用する第3エディション。pi 0.84.2で検証。
必要: Node（piの対応版）、bash、git、jq、pi、インストール済みqwenmagi。
repo全体を保ち、対象リポジトリ内から起動する。新しいnpm依存やアカウントは不要。

```sh
VDGG_PI_BIN=/path/to/pi bash /path/to/VibesDeGoGo/pi/vdgg-pi.sh \
  --provider qwen-provider --model Qwen-model-id --thinking off
```

piがPATHにあればVDGG_PI_BINは不要。`QWENMAGI_SKILL_DIR`の既定は
`~/.agents/skills/qwenmagi`。異なる場所ならそのskillディレクトリを指定する。
モデルと接続は既存piのmodels.json/PI_CODING_AGENT_DIRを使う。スクリプトは変更しない。
Thinkingと出力上限は実モデルで検証し、長いpatchは小さいtaskへ分ける。

pi版skillとqwenmagi、VDGG拡張を明示ロードし、通常のskill/extension自動探索を無効化する。
Orca等の追加拡張が必要なら `--extension /path/to/extension` を明示する。
`/skill:vibesdegogo-pi` で依頼する。拡張が各LLM呼び出しに現在stateと当該Stepだけを渡す。
既存AGENTS.mdの要件合意と規律は引き続き適用される。

native readは成功後に証拠化。Bash read失敗時は事前記録を戻す。同一応答の2件目以降の
ツールは拒否し、次の応答で実行する。native edit/writeは既存patch-firstゲートに従う。
通常終了でactive stateが残っていれば継続を要求する。stateの変化も成功ツールもない再開は最大3回。
上限時は明示停止メッセージを残し、未完了stateを保持する。ツール/拡張を意図的に無効化
する行為や、既存shell hookが識別できないinterpreter経由の書込を防ぐサンドボックスではない。

stateと成果物はCodex版と同じ `.codex/.vdgg-*` と `tasks/vdgg/{id}/`。
**同一repo rootでCodex/Claude/piのVDGGを並行実行しない。** 別worktreeを使う。
hook/helperの故障で通過したとは扱わない。停止理由を調べ、修復後にpiを再開する。
qwenmagiの無指定席は起動中のQwen。外部席は既存qwenmagiの分離/応答検証を使う。
同じモデルの3人格を別モデル間の独立性とは呼ばない。

```sh
bash tests/test-pi-adapter.sh
bash tests/run-all.sh
```
