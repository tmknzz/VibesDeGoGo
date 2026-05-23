# VibeDeGoGo!

VibeDeGoGo! is a state-and-hook workflow for Claude Code that keeps AI coding agents moving until the work is actually done, while stopping only before constraint violations.

It exists because vibe coding is powerful, but AI agents can skip the boring parts: requirements, investigation, verification, and clear handoff. VibeDeGoGo! turns those parts into rails.

The core idea:

- do not stop for progress confirmation
- do stop before constraint violations
- write requirements before implementation
- investigate existing code before planning
- verify before completion
- use state files and hooks so the workflow is enforced mechanically, not just by prompt text

## What It Is

VibeDeGoGo! is designed for practical AI-assisted coding sessions where the user wants to make one request and have the agent carry it through:

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
- **Push behavior is workflow-specific:** default `branch-pr` pushes the feature branch to create a PR; `trunk` pushes only when `.vdg-target` sets `AUTO_PUSH=true`.

## Modes

- **Full flow:** default for normal coding work.
- **Self-maintenance mode:** only for changes under `skills/vibedegogo/`; keeps VibeDeGoGo! self-edits focused while preserving core checks.
- **Lightweight mode:** for small, closed changes in general projects. It still requires fixed scope, existing patterns, no new dependencies, and explicit verification. It escalates to full flow when tests fail twice, scope expands, or specification judgment is needed.
- **Friendly completion reports:** final messages start with plain-language status and next steps, with Git details separated into a short technical note.

## Repository Layout

```text
skills/vibedegogo/
  SKILL.md
  scripts/
    vdg-state.sh
    vdg-hook-pretool.sh
    vdg-hook-posttool.sh
    vdg-hook-stop.sh
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
cp -R skills/vibedegogo "$HOME/.claude/skills/vibedegogo"
```

Then register the hooks shown in:

```text
skills/vibedegogo/references/setup.md
```

`jq` is required because the hooks parse Claude Code hook JSON.

## Project Configuration

For each project, optionally create `.vdg-target` in the project root. See:

```text
skills/vibedegogo/references/target_schema.md
```

The most important optional workflow fields are:

```bash
WORKFLOW=branch-pr
AUTO_PUSH=false
```

With the default `WORKFLOW=branch-pr`, Step 9 pushes the feature branch so it can open a PR. `AUTO_PUSH=true` only affects `WORKFLOW=trunk`.

## Why Free

VibeDeGoGo! is free and open source.

Vibe coding gave me a way to build with joy. This project is my small thank-you back to that world: a set of safety rails so more people can enjoy building with AI without feeling lost or unsafe.

## Status

This is an opinionated workflow extracted from real daily use. It is not a general-purpose CI/CD system. It is a guardrailed operating procedure for AI coding agents.
