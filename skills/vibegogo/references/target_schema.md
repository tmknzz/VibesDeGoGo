# [VibeGoGo 参照: .fop-target スキーマ]

このファイルは SKILL.md 本体から切り出された詳細補足。

## `.fop-target` スキーマ（KEY=VALUE 形式、bash source 可能）

Step 8 の具体的な手順は **プロジェクトルートの `.fop-target`**（VibeGoGo ターゲット設定ファイル）で決まる。設定ファイルが無いプロジェクトではバージョン更新をスキップし、検証依頼のみ行う。

```bash
# バージョン更新対象ファイル（複数指定可、連番 _1_, _2_, ...）
VERSION_FILE_1_PATH=<プロジェクトルートからの相対パス>
VERSION_FILE_1_KEY=<そのファイル内で更新するキー名>
VERSION_FILE_2_PATH=...
VERSION_FILE_2_KEY=...

# バージョン書式（エージェントが新しい値を生成するときの指針）
VERSION_FORMAT="<人間向け説明>"
VERSION_EXAMPLE="<例値>"

# 検証方法
DEPLOY_COMMAND="<デプロイに使う slash command or 手順>"
DEPLOY_TARGET="<実機 / ローカル / dev環境 等>"
VERIFY_TYPE="<実機プレビュー / ブラウザ確認 / curl で叩く 等>"

# コミット後の push 方針（任意）
# true の場合のみ Step 9 で git push する。未設定 / false / その他の値では push しない。
AUTO_PUSH=false

# プロジェクト固有のテストコマンドパターン（任意）
# implementing phase でエージェント発の実行をブロックするための拡張正規表現。
# デフォルトの swift test / xcodebuild test / pytest / npm test / pnpm test / yarn test /
# go test / cargo test / jest / vitest / mocha に加えて、プロジェクト固有のカスタム
# テストコマンド（例: `make test-unit`）を追加で検出できる。
# 値は grep -E に渡される拡張正規表現の本体（既存パターンに `|` で連結される）。
TEST_COMMAND_PATTERN="<追加で検出したい正規表現、例: make[[:space:]]+test-unit>"
```

## 例（iOS / TimeCamera）

```bash
VERSION_FILE_1_PATH=project.yml
VERSION_FILE_1_KEY=CURRENT_PROJECT_VERSION
VERSION_FILE_2_PATH=Sources/TimeCameraApp/Service/AnalyticsService.swift
VERSION_FILE_2_KEY=buildVersion
VERSION_FORMAT="yyyymmdd + 連番アルファベット"
VERSION_EXAMPLE="20260417D"
DEPLOY_COMMAND="/deploy-device"
DEPLOY_TARGET="実機"
VERIFY_TYPE="実機プレビュー"
AUTO_PUSH=false
```

## 例（Mac アプリ）

```bash
VERSION_FILE_1_PATH=MyApp/Info.plist
VERSION_FILE_1_KEY=CFBundleVersion
VERSION_FORMAT="semver + build"
VERSION_EXAMPLE="1.0.0.42"
DEPLOY_COMMAND="/deploy-mac"
DEPLOY_TARGET="ローカルMac"
VERIFY_TYPE="ローカル起動確認"
AUTO_PUSH=false
```

## 例（Web バックエンド、バージョンファイル不要）

```bash
# VERSION_FILE_* を空にすればバージョン更新をスキップ
DEPLOY_COMMAND="npm run dev"
DEPLOY_TARGET="dev サーバー"
VERIFY_TYPE="ブラウザ確認"
AUTO_PUSH=false
```

## Step 8 での読み込み手順

```bash
if [ -f "$(pwd)/.fop-target" ]; then
    source "$(pwd)/.fop-target"
fi
```

各 `VERSION_FILE_N_PATH` のファイルの `VERSION_FILE_N_KEY` を更新。新しい値は `VERSION_FORMAT` / `VERSION_EXAMPLE` を参考に生成。**必ず最新コミットより新しい値にする**（`git show HEAD:<path> | grep <key>` で現状確認）。`.fop-target` が無い場合はこのステップ全体をスキップ。

## Step 9 での push 方針

Step 9 では `.fop-target` の `AUTO_PUSH` を読み、`AUTO_PUSH=true` の場合のみ `git push` する。未設定、`false`、その他の値では push しない。push しなかった場合は完了報告で「push 未実行（AUTO_PUSH 未設定）」または「push 未実行（AUTO_PUSH=false）」を明記する。
