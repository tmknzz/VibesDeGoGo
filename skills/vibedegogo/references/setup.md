# VibeDeGoGo! Reference: Setup

This file explains how to install VibeDeGoGo! in a Claude Code environment.

## 1. Dependencies

Required:

- `jq`: hooks parse Claude Code hook JSON with `jq`.
- `bash`, `date`, `tr`, `grep`, `sed`: available by default on macOS-like environments.

Install `jq` on macOS:

```bash
brew install jq
```

The hooks fail closed when `jq` is missing, except for a narrow `brew install jq` recovery path.

## 2. Install The Skill

Copy the skill folder:

```bash
mkdir -p "$HOME/.claude/skills"
cp -R skills/vibedegogo "$HOME/.claude/skills/vibedegogo"
```

## 3. Register Hooks In `~/.claude/settings.json`

Add a PreToolUse hook:

```json
{
  "matcher": "",
  "hooks": [
    {
      "type": "command",
      "command": "bash $HOME/.claude/skills/vibedegogo/scripts/vdg-hook-pretool.sh",
      "timeout": 5
    }
  ]
}
```

Also register PostToolUse, PostToolUseFailure, and Stop hooks:

```json
"PostToolUse": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "bash $HOME/.claude/skills/vibedegogo/scripts/vdg-hook-posttool.sh",
        "timeout": 5
      }
    ]
  }
],
"PostToolUseFailure": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "bash $HOME/.claude/skills/vibedegogo/scripts/vdg-hook-posttool.sh",
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
        "command": "bash $HOME/.claude/skills/vibedegogo/scripts/vdg-hook-stop.sh",
        "timeout": 5
      }
    ]
  }
]
```

PostToolUse must match all tools, not only Bash. It must observe `Skill` calls for simplify and `Edit`/`Write` calls after simplify.

## 4. Project Setup

Optionally create `.vdg-target` in the project root. See `target_schema.md`.

The `.claude/` directory is created automatically by `vdg_state_init`.

## 5. Coexistence

Do not run multiple formation workflows in the same repository at the same time. Clear the previous state with `vdg_state_clear` before switching workflows.
