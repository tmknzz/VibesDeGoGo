[English](CONTRIBUTING.md) | **日本語**

# コントリビューションガイド

VibesDeGoGo! の改善にご協力ありがとうございます。本プロジェクトは意図的に小規模に保たれており、shell スクリプトと Markdown ドキュメントのみで構成され、テストフレームワークへの依存はありません。

## 必要環境

- `bash`
- `jq`
- 標準 Unix ツール: `date`, `tr`, `grep`, `sed`, `find`, `awk`

macOS の場合、`jq` は次でインストールできます:

```bash
brew install jq
```

## リポジトリ構成

- `skills/vibesdegogo/`: Claude Code エディション
- `.agents/skills/vibesdegogo/`: Codex エディション
- `skills/vibesdegogo/scripts/`: Claude 用の hook と state ヘルパー
- `.agents/skills/vibesdegogo/scripts/`: Codex 用の hook と state ヘルパー
- `skills/vibesdegogo/references/edition_parity.md`: Claude / Codex 両エディションで揃えるべき項目
- `tests/`: 依存ゼロの smoke テスト

## テストの実行

全 smoke テスト:

```bash
bash tests/run-all.sh
```

個別ファイル:

```bash
bash tests/test-state.sh
bash tests/test-hook-pretool.sh
bash tests/test-hook-posttool.sh
bash tests/test-hook-stop.sh
```

スクリプト編集時の構文チェック:

```bash
bash -n skills/vibesdegogo/scripts/*.sh
bash -n .agents/skills/vibesdegogo/scripts/*.sh
```

## hook スクリプトの編集について

hook / state スクリプト内のコメントに対して、広域 `sed -i` での書き換えは行わないでください。過去にリネーム作業で意味のあるコメントが汎用 placeholder に置き換えられてしまった経緯があります。名前やコメントを変更する際は:

- diff をファイル単位で確認する
- 振る舞いの変更とコメントだけの変更は別コミットに分ける
- 共有ワークフロー契約が変わる時は両エディションを揃えて更新する
- merge 前に `skills/vibesdegogo/references/edition_parity.md` を確認する

## commit スタイル

以下の形式を使ってください:

```text
{type}: {summary}
```

よく使う type: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

## Pull Request

PR を開く前に:

- `bash tests/run-all.sh` を走らせる
- 変更したスクリプトの構文チェックを走らせる
- 変更が Claude / Codex / 両方のどれに影響するか明記する
- 共有ワークフロー契約に変更がある場合は edition parity ドキュメントを更新する

## バージョニング

skill ファイル内の `version` フィールドは、当該エディションのワークフロー仕様を追跡します。リポジトリのリリースは別途 SemVer タグで管理しており、最初のパブリック OSS リリースは `0.1.0` から始まります。
