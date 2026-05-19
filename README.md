# VibeGoGo

VibeGoGo is a state-and-hook workflow for Claude Code that keeps AI coding agents moving until done while stopping only for constraint violations.

The core idea:

- do not stop for progress confirmation
- do stop before constraint violations
- write requirements before implementation
- investigate existing code before planning
- verify before completion
- use state files and hooks so the workflow is enforced mechanically, not just by prompt text

## What It Is

VibeGoGo is designed for practical AI-assisted coding sessions where the user wants to make one request and have the agent carry it through:

1. agree on Goal / Constraints / Acceptance criteria
2. write `requirements.md`
3. investigate the codebase and write `investigation.md`
4. create `todo.md` and `progress.md`
5. implement one task at a time
6. test or otherwise verify
7. reflect and retry on failures
8. update progress and version metadata
9. commit, and optionally push

It is intentionally strict on the agent side and lightweight on the user side.

## Key Rules

- **No progress confirmation:** the agent must not stop with "Can I continue?"
- **Constraint confirmation required:** the agent must stop before changing constraints, adding dependencies, using non-standard implementations, changing persistence/API/billing/analytics contracts, touching security-sensitive behavior, or performing destructive operations.
- **Standard-first:** use the platform/framework standard components, APIs, and patterns first. If that is not enough, report the reason and alternatives before implementation.
- **Verification required:** do not mark a task complete without tests, build verification, smoke checks, or explicit manual verification steps where automation is not possible.
- **Push is opt-in:** `git push` runs only when `.fop-target` sets `AUTO_PUSH=true`.

## Repository Layout

```text
skills/vibegogo/
  SKILL.md
  scripts/
    fop-state.sh
    fop-hook-pretool.sh
    fop-hook-posttool.sh
    fop-hook-stop.sh
  references/
    setup.md
    output_formats.md
    target_schema.md
    hook_rules.md
    state_helpers.md
    subagent_prompts.md
```

## Install

Copy the skill folder into Claude Code's skills directory:

```bash
mkdir -p "$HOME/.claude/skills"
cp -R skills/vibegogo "$HOME/.claude/skills/vibegogo"
```

Then register the hooks shown in:

```text
skills/vibegogo/references/setup.md
```

`jq` is required because the hooks parse Claude Code hook JSON.

## Project Configuration

For each project, optionally create `.fop-target` in the project root. See:

```text
skills/vibegogo/references/target_schema.md
```

The most important optional field is:

```bash
AUTO_PUSH=false
```

Only `AUTO_PUSH=true` allows Step 9 to run `git push`.

## Status

This is an opinionated workflow extracted from real daily use. It is not a general-purpose CI/CD system. It is a guardrailed operating procedure for AI coding agents.

