# Kickoff prompt for the build session

Paste everything inside the block below into a fresh session (Cursor cloud agent, Claude Code or Codex). Fill in the two `GRANTS` lines first.

```text
You are the orchestrator for MagicSim, Tanner's personal iPhone app for playing 4-player Commander against three Claude-controlled opponents, with Forge as the rules engine. Your job is to build it milestone by milestone with as little human input as possible, and to leave every milestone in a state Tanner can verify from git and the PRs alone.

Repo: https://github.com/tanner-pham/MagicSim
Start point: if PR #1 (docs/initial-plan) is merged, branch from main; otherwise branch from docs/initial-plan and target your PRs at it.

GRANTS (Tanner edits these two lines before pasting):
- Merge: NOT granted. Never merge a PR.
- Deploy / paid actions (Fly deploy, EAS Build, EAS Simulator, TestFlight submit): NOT granted.

Always granted: creating branches and worktrees, pushing, opening and updating draft PRs, flipping PRs to ready when their gate is met, adding the dependencies named in the spec or a milestone plan, and running anything local.

1. Read, in order: AGENTS.md, ARCHITECTURE.md, docs/superpowers/specs/2026-10-13-magicsim-design.md, docs/superpowers/plans/2026-10-13-magicsim-roadmap.md, docs/STATUS.md. AGENTS.md's hard rules override anything here: never edit forge/, never decide legality outside Forge, protocol changes start in packages/protocol, no secrets or card images in the repo.

2. Environment: run `bash scripts/setup.sh`, then `bash scripts/verify.sh`. Both must succeed before you write code. If setup fails, fix the script (not forge/) and record what changed.

3. Work through the roadmap. M0 and M1 already have a detailed plan: docs/superpowers/plans/2026-10-13-m0-m1-foundation-and-forge-spike.md. Its Java was compiled and run against the pinned Forge before handoff, so port it as written; if a step fails, debug with the notes at the top of that plan before changing the design. For every later milestone, first write its detailed plan with superpowers:writing-plans, commit it, then implement.

4. Per milestone:
   - New worktree and branch (`feat/m<N>-<slug>`). If the previous milestone's PR is not merged yet, branch from it and set it as the PR base (stacked PRs).
   - Open a draft PR immediately, linking the milestone plan and carrying a checklist.
   - Implement with superpowers:subagent-driven-development and test-driven development. Give each subagent an owned-path fence.
   - Run the milestone's evidence gate from the roadmap. Verify against builds, not dev servers: `bash scripts/verify.sh`, the bridge jar, and the web export for app work. For UI, take Playwright screenshots of the web build at 402x874 and 626x890 and compare them with docs/design/screenshots/.
   - When the gate is met: update the PR body with real evidence (commands, pass counts, screenshots) in the writing-prs template, flip it to ready, then run a reviewing-code pass and fix the findings.
   - Update docs/STATUS.md using the handoff template in AGENTS.md and commit it.

5. Parallelism: M5 (app shell and decks) only needs packages/protocol and fixture observations, so run it alongside M1 to M4 in its own worktree.

6. Secrets: ANTHROPIC_API_KEY (from M4), EXPO_TOKEN, FLY_API_TOKEN and an App Store Connect API key (M7). Read them from the environment only. If one is missing when a step needs it, that step is BLOCKED: record it and move to the next unblocked milestone.

7. Stop conditions (record BLOCKED in docs/STATUS.md, then continue with other unblocked work): a missing secret; the same failure 3 times with no new hypothesis; a fix that would need an edit inside forge/; a merge, deploy or paid action not granted above. Do not loop.

8. When you run out of unblocked work, end with a report in exactly this shape:
   - Verified: each milestone gate met, with evidence links (PRs, CI runs, screenshots).
   - Not verified: what wasn't verified, and why.
   - For Tanner: the exact actions needed (secrets to add, PRs to review or merge, grants to give), in the order that unblocks the most work.
```

## Notes for Tanner

- With merge and deploy not granted, a full run ends with a stack of ready PRs for M0 through M6, each with evidence. M7 (Fly deploy and TestFlight) and anything that needs `ANTHROPIC_API_KEY` stop at BLOCKED until you add the secret or the grant.
- For a cloud agent, add the secrets in the agent environment's secret settings, not in the repo. `.cursor/environment.json` already builds the image and runs `scripts/setup.sh`.
- Card art comes from Scryfall at runtime, so nothing needs to be set up for images.
