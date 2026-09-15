# VibesDeGoGo! Reference: Setup

This file explains how to install VibesDeGoGo! in a Claude Code environment.

## 0. Plugin Install (Recommended)

The repository is packaged as a Claude Code plugin: installing it registers the skill AND activates the hooks automatically — no settings.json editing.

```text
/plugin marketplace add tmknzz/VibesDeGoGo
/plugin install vibesdegogo@vibesdegogo
```

`jq` is still required (see Dependencies). The manual install below remains supported for environments without plugin support and for developing VibesDeGoGo! itself.

## 1. Dependencies

Required:

- `jq`: hooks parse Claude Code hook JSON with `jq`.
- `bash`, `date`, `tr`, `grep`, `sed`: available by default on macOS-like environments.

Install `jq` on macOS:

```bash
brew install jq
```

When `jq` is missing, the hooks stay out of the way in repositories without an active VibesDeGoGo! session, so global registration never blocks unrelated work. With an active session they fail closed, except for a narrow `jq` install recovery path (`brew install jq`, `apt-get install jq`, etc.).

## 2. Install The Skill

Copy the skill folder:

```bash
mkdir -p "$HOME/.claude/skills"
cp -R skills/vibesdegogo "$HOME/.claude/skills/vibesdegogo"
```

## 3. Register Hooks In `~/.claude/settings.json`

Add a PreToolUse hook:

```json
{
  "matcher": "",
  "hooks": [
    {
      "type": "command",
      "command": "bash $HOME/.claude/skills/vibesdegogo/scripts/vdgg-hook-pretool.sh",
      "timeout": 5
    }
  ]
}
```

Also register PostToolUse, PostToolUseFailure, and Stop hooks:

```json
"PostToolUse": [
  {
    "matcher": "Bash|Skill|Edit|Write",
    "hooks": [
      {
        "type": "command",
        "command": "bash $HOME/.claude/skills/vibesdegogo/scripts/vdgg-hook-posttool.sh",
        "timeout": 5
      }
    ]
  }
],
"PostToolUseFailure": [
  {
    "matcher": "Bash|Skill|Edit|Write",
    "hooks": [
      {
        "type": "command",
        "command": "bash $HOME/.claude/skills/vibesdegogo/scripts/vdgg-hook-posttool.sh",
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
        "command": "bash $HOME/.claude/skills/vibesdegogo/scripts/vdgg-hook-stop.sh",
        "timeout": 5
      }
    ]
  }
]
```

PostToolUse and PostToolUseFailure must observe Bash, Skill, Edit, and Write.
Keep these matchers aligned with the tool filter in vdgg-hook-posttool.sh.
PreToolUse must continue to match all tools: vdgg-hook-pretool.sh also checks
unknown tools that expose file_path or notebook_path. A fixed list of known
write tools would bypass those guards. Keep its read-only fast paths as well.

## 4. Project Setup

Optionally create `.vdgg-target` in the project root. See `target_schema.md`.

The `.claude/` directory is created automatically by `vdgg_state_init`.

## 5. Coexistence

Do not run multiple formation workflows in the same repository at the same time. Clear the previous state with `vdgg_state_clear` before switching workflows.
