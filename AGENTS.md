# AGENTS.md

Instructions for any agent (Cursor, Claude Code, Codex) working in this repo. `ARCHITECTURE.md` is the authority on stack and boundaries; this file is the authority on workflow.

## Read first, in order

1. `ARCHITECTURE.md`
2. `docs/superpowers/specs/2026-10-13-magicsim-design.md` (the spec)
3. `docs/superpowers/plans/2026-10-13-magicsim-roadmap.md` (milestones and gates)
4. The detailed plan for the milestone you're on (`docs/superpowers/plans/*-m<N>-*.md`)
5. `docs/STATUS.md` (where the last session stopped)

## Commands

| Task | Command |
|---|---|
| One-time / refresh setup | `bash scripts/setup.sh` |
| Verify everything that exists | `bash scripts/verify.sh` |
| Bridge build | `.tools/apache-maven-3.9.11/bin/mvn -f bridge/pom.xml package` |
| JS (from repo root) | `pnpm -r typecheck`, `pnpm -r lint`, `pnpm -r test` |
| App in a browser | `pnpm --filter app web` |

Requires Java 17+ (Temurin 21 recommended) and Node 24. Maven is pinned and installed into `.tools/` by setup.

## Hard rules

- **Never edit `forge/`.** It's a pinned upstream submodule. See ARCHITECTURE.md "Forge patches".
- **Never decide legality outside Forge.** If you are writing code that checks whether something is legal, stop; get it from the bridge.
- **Protocol changes start in `packages/protocol`**, then the Java records, then the contract test.
- **No secrets in the repo.** `.env` is gitignored; `.env.example` lists names only.
- **No card images in the repo.** Runtime loads from Scryfall only. Decklists (card names) are fine.
- **TypeScript:** strict, no `any`, no `as` casts, no weakened types to make something compile.
- **React:** one component per file (`PascalCase.tsx`), a named `Props` interface above the component, `props.x` access, `is`/`has` boolean prefixes, `on`-prefixed handlers, early returns for loading/error/empty, complex state in a colocated custom hook. Components own their loading/error/empty states.
- **Errors:** catch specific types; messages formatted `[Module:Function] Description — {context}` with no secrets.
- **UI copy:** plain and factual. No em dashes in user-facing text, no "AI-powered"/"magic"/sparkle language, no "Thinking…" (use "Waiting for Sonnet", "Loading…"). Plurals correct ("1 card", "2 cards").
- **Visual spec:** `docs/design/mockups/board.html` + `docs/design/screenshots/`. Tokens come from the mockup's `:root`. Black background, white text, fades instead of borders.
- **Intentional shortcuts** get a `ponytail:` comment naming the ceiling and the upgrade path.

## Workflow

- Work in a git worktree under `.worktrees/` on a branch, never in the main checkout.
- Each milestone branch opens a **draft PR first**, linking its plan file and carrying a checklist. Keep the body current.
- Conventional, atomic commits. No self-attribution. Never force-push or amend pushed commits.
- TDD for bridge, protocol and server logic: failing test, minimal code, passing test, commit.
- Before writing a milestone's code, write its detailed plan (`docs/superpowers/plans/YYYY-MM-DD-m<N>-<name>.md`) grounded in the code as it exists then.
- Flip a PR to ready only with evidence: exact test commands and pass counts, typecheck, and screenshots from a real build for any UI change.
- **Never merge** unless Tanner (or the kickoff grant) explicitly says so. Never merge on red.

## Verification evidence (what "done" means)

- Bridge/server: `scripts/verify.sh` output with pass counts.
- Full game: the headless 4-player game reaches `gameOver` with 0 `unmapped` decisions.
- UI: Playwright screenshots of the web build at 402×874, 466×678 and 626×890, compared against the mockups.
- Real iOS (when `EXPO_TOKEN` is available): EAS Simulator screenshots of the actual build.
- State plainly what was not verified and why.

## Handoff (`docs/STATUS.md`)

Update at the end of every session or milestone so the next session resumes from git alone:

```
Status: DONE | DONE_WITH_CONCERNS | BLOCKED
Milestone: M<N> <name> · Branch: <branch> · PR: <url> · Last SHA: <sha>
Decisions made without approval: …
Skipped (with reason): …
Remaining + how to verify: …
Blocked on Tanner: …
```

## Stop conditions

Stop and record BLOCKED in `docs/STATUS.md` (then move to the next unblocked milestone) when: a required secret is missing, the same failure repeats 3 times with no new hypothesis, a fix would require editing `forge/`, or a step needs a merge, deploy, or paid action that was not granted.
