# Copilot instructions

Authoritative guidance for AI coding agents in this repo lives in **`AGENTS.md`** (read it
first), with the code map in `CLAUDE.md` and the roadmap in `docs/development-plan.md`.
This file is just a pointer — keep the actual rules in `AGENTS.md` to avoid drift.

**Working agreement — document first, then code, then record.** Before a change (even a
small one), note the plan in `docs/worklog.md` (and update `docs/development-plan.md` if
it's roadmap-level); after, fill the worklog's *Done* + *Next* and fix any docs that
drifted, in the same change. The next agent should understand what was planned, what
shipped, and what's next from the docs alone.

Practical: run `dart format .` before committing (CI gate is format → analyze → test);
develop on a feature branch; the app version is duplicated — see the sync list in
`AGENTS.md` / `CLAUDE.md`. UI strings and widget tests are in Russian.
