# VibesDeGoGo! for Codex Setup

## Install as a repo-local skill

Codex reads repo skills from `.agents/skills` under the current directory or repository root. This repository includes:

```text
.agents/skills/vibesdegogo/
```

Restart Codex if the skill does not appear after checkout or edits.

## Enable hooks

The repository includes `.codex/hooks.json`. Codex loads project-local hooks only after the project `.codex/` layer is trusted. Use `/hooks` in Codex to review and trust the hook definitions.

`jq` is required because the hook scripts parse Codex hook JSON.

## Verified upstream behavior

The Codex docs say:

- skills are directories with `SKILL.md` and optional `scripts/`, `references/`, `assets/`, and `agents/`;
- Codex reads repo skills from `.agents/skills`;
- Codex loads hook sources from `~/.codex/hooks.json`, `~/.codex/config.toml`, `<repo>/.codex/hooks.json`, and `<repo>/.codex/config.toml`;
- `PreToolUse` and `PostToolUse` can observe `Bash`, `apply_patch`, and MCP tool calls, but this is a guardrail rather than a complete enforcement boundary.

Sources:

- https://developers.openai.com/codex/skills
- https://developers.openai.com/codex/hooks
- https://github.com/openai/codex/releases/tag/rust-v0.124.0

## Known limitation

VibesDeGoGo! for Codex follows the Claude Code step model, but hook parity is not exact. The Codex hook docs explicitly warn that `PreToolUse` is a guardrail rather than a complete enforcement boundary. Treat hooks as safety rails, not a sandbox or proof of correctness.

