**English** | [日本語](CONTRIBUTING.ja.md)

# Contributing

Thanks for improving VibesDeGoGo!. This project is intentionally small: shell
scripts, Markdown docs, and no test framework dependency.

## Requirements

- `bash`
- `jq`
- standard Unix tools: `date`, `tr`, `grep`, `sed`, `find`, `awk`

On macOS, install `jq` with:

```bash
brew install jq
```

## Repository Layout

- `skills/vibesdegogo/`: Claude Code edition.
- `.agents/skills/vibesdegogo/`: Codex edition.
- `skills/vibesdegogo/scripts/`: Claude hook and state helpers.
- `.agents/skills/vibesdegogo/scripts/`: Codex hook and state helpers.
- `skills/vibesdegogo/references/edition_parity.md`: what must stay aligned
  between the Claude and Codex editions.
- `tests/`: zero-dependency smoke tests.

## Running Tests

Run the full smoke suite:

```bash
bash tests/run-all.sh
```

Run one file:

```bash
bash tests/test-state.sh
bash tests/test-hook-pretool.sh
bash tests/test-hook-posttool.sh
bash tests/test-hook-stop.sh
```

Run syntax checks when editing scripts:

```bash
bash -n skills/vibesdegogo/scripts/*.sh
bash -n .agents/skills/vibesdegogo/scripts/*.sh
```

## Editing Hook Scripts

Do not use broad `sed -i` rewrites for hook or state script comments. A previous
rename damaged meaningful comments by replacing them with a generic placeholder.
When changing names or comments:

- inspect the diff by file;
- keep behavior changes separate from comment-only changes;
- update both editions when the shared workflow contract changes;
- check `skills/vibesdegogo/references/edition_parity.md` before merging.

## Commit Style

Use:

```text
{type}: {summary}
```

Common types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.

## Pull Requests

Before opening a PR:

- run `bash tests/run-all.sh`;
- run syntax checks for changed script sets;
- note whether the change affects Claude, Codex, or both;
- update edition parity docs if the shared workflow contract changed.

## Versioning

The `version` field inside a skill file tracks the workflow specification for
that edition. Repository releases use separate SemVer tags, starting at `0.1.0`
for the first public OSS release.
