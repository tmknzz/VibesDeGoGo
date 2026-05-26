# Changelog

This project follows the structure of Keep a Changelog:
https://keepachangelog.com/en/1.1.0/

## [Unreleased]

### Added

- Zero-dependency bash smoke tests for state helpers and hook phase guards.
- Claude/Codex edition parity documentation.
- Contribution guide and GitHub issue/PR templates.

### Fixed

- Restored meaningful Claude hook/state script comments damaged during rename.
- Replaced the leftover legacy formation regex with `vdgg_state_*` matching.
- `PostToolUseFailure` posttool branch now honors the same `IS_SEARCH`
  exception as the standard `EXIT_CODE` branch, so search no-match (exit 1)
  from `grep`/`find`/etc. no longer raises the error-pending flag and
  blocks follow-up tools.
- Pretool's direct state-file edit guard treats fd-merge redirects
  (`2>&1`, `>&2`) as non-destructive by changing the redirect detector
  from `>` to `>[^&]`. Diagnostic commands that merely mention state-file
  paths now pass through.
- Pretool's direct state-file edit guard exempts `git commit`, so a commit
  message that legitimately mentions a state-file path is no longer
  treated as a destructive edit. Other commit-phase rules still apply.
- Posttool's testing-phase Edit/Write tracking now excludes the simplify
  sentinel itself, preventing a self-referential `modified=1` loop when
  the sentinel is created via Edit/Write (e.g. environments without the
  `simplify` Skill tool).
- Codex pretool received the same redirect and `git commit` exemptions
  for parity.

## [0.1.0] - 2026-05-25

### Added

- VibesDeGoGo! for Claude Code.
- VibesDeGoGo! for Codex.
- Branch/PR workflow defaults.
- Reflection loop and verification gates.
- Self-maintenance and lightweight mode documentation.
