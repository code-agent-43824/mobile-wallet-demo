# AGENTS.md — start here

This repository is developed by **multiple coding agents (Claude Code and others),
sometimes in parallel**. Read this file first, then `CLAUDE.md` and
`docs/development-plan.md`.

## Working agreement — document first, then code, then record

1. **Document first.** Before writing code — even a small chunk — record the plan:
   add an entry to `docs/worklog.md`, and update `docs/development-plan.md` when the
   work is roadmap-level. Say what you intend to do and why.
2. **Then do the work.**
3. **Then record results** in the same change: fill the worklog entry's *Done* and
   *Next / open*, update the plan's status/checkboxes, and fix any docs that drifted
   (architecture, version, etc.).

Goal: the next agent can tell **what was planned, what shipped, and what's next from
the docs alone** — without reading the diff. If code and docs disagree, fix the docs
in the same change. Keep changes small and self-contained so a parallel/next agent can
pick up cleanly.

## Where things live

| File | Purpose |
| --- | --- |
| `CLAUDE.md` | Accurate map of the code: architecture, commands, conventions, gotchas. |
| `docs/development-plan.md` | Canonical roadmap: phase status, current stopping point, next steps. |
| `docs/worklog.md` | Append-only granular log of each work chunk (plan → done → next). |
| `README.md` | Feature overview (UI strings are Russian). |

## Practical notes

- Toolchain (pinned in `.github/workflows/ci.yml`): Flutter 3.41.7, Dart `^3.11.0`, Java 17.
- Run `dart format .` before committing — the CI `validate` job (format → analyze → test)
  fails on unformatted code. Platform builds (Android/iOS/Windows) run only after `validate`.
- Develop on a feature branch. `main` is **not** required to stay green, but record any
  breakage and fix forward.
- The app version is duplicated; bumping it means updating `pubspec.yaml`,
  `lib/src/app_version.dart`, `test/widget_test.dart` (asserts the on-screen label),
  `README.md`, and the `docs/development-plan.md` "Current stopping point".
