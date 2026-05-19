# [VibeGoGo 参照: セットアップ手順]

このファイルは SKILL.md 本体から切り出された詳細補足。

## セットアップ（新環境導入時）

VibeGoGo を新しい Mac / 新規ユーザーで使う場合に必要な手順。

### 1. 依存コマンド

- `jq` 必須（hook が JSON パースに使う。**jq が無いと hook が黙ってスルーされ、物理強制が効かない**）
  ```bash
  brew install jq   # macOS
  ```
- `bash` 4+ / `date` / `tr` / `grep` / `sed`（標準環境で入っている）

### 2. `~/.claude/settings.json` への PreToolUse hook 登録

`hooks.PreToolUse` に以下を追加:

```json
{
  "matcher": "",
  "hooks": [
    {
      "type": "command",
      "command": "bash $HOME/.claude/skills/vibegogo/scripts/fop-hook-pretool.sh",
      "timeout": 5
    }
  ]
}
```

※ VibeGoGo 本家と併用する場合は、同名の hook は 1 つに絞る（複数入れると両方走って state file 衝突を誘発する）

加えて PostToolUse / Stop hook も登録する:

```json
"PostToolUse": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "bash $HOME/.claude/skills/vibegogo/scripts/fop-hook-posttool.sh",
        "timeout": 5
      }
    ]
  }
],
"Stop": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "bash $HOME/.claude/skills/vibegogo/scripts/fop-hook-stop.sh",
        "timeout": 5
      }
    ]
  }
]
```

PostToolUse の matcher は `""`（全 tool）。testing phase 中の Skill simplify 起動と Edit/Write を捕捉して sentinel ファイル（`.fop-simplify-sentinel-{id}-{loop_count}`）を作成・更新するため、Bash 限定では足りない。phase != testing の場合はスクリプト冒頭で早期 return することで他 phase での hook 起動オーバーヘッドを軽量化している。

Stop hook の役割: VibeGoGo サイクル中（state file アクティブ）に最終 assistant ターンが `fop_state_(advance|loop|write|clear|init)` 呼出も `【意図的停止】` テキストも含まないままターン終了しようとした場合、exit 2 でブロックして「次のアクションを実行 or 意図的停止を明示せよ」と差し戻す。これによりフォーメーション中の「うっかり停止」を物理的に防ぐ。

### 3. プロジェクト側セットアップ

VibeGoGo を適用したいプロジェクトで:

- プロジェクトルートで `.fop-target` を作成（`references/target_schema.md` のスキーマを参照、不要なプロジェクトは作らなくていい）
- `.claude/` ディレクトリは `fop_state_init` 実行時に自動で作られる

### 4. 他フォーメーション skill との共存

同リポジトリで **VibeGoGo と他のフォーメーション skill を同時に走らせない**。VibeGoGo 自体は state file が `.claude/.fop-*` で他フォーメーションと衝突しない設計だが、複数フォーメーションを並走させると人間側（エージェント）の混乱で進行が崩れる。使う skill を1つに絞るか、前回の state を `fop_state_clear` で片付けてから切り替える。
