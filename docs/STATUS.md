Status: DONE
Milestone: planning (before M0) · Branch: docs/initial-plan · PR: https://github.com/tanner-pham/MagicSim/pull/1 · Last SHA: see `git log -1`
Decisions made without approval: reference decks are four Forge precons (see the roadmap); all automated games take a turn limit and end as a draw past it; Forge is installed with `flatten-maven-plugin` so its `${revision}` POMs resolve.
Skipped (with reason): none.
Remaining + how to verify: start M0 Task 1 in `docs/superpowers/plans/2026-10-13-m0-m1-foundation-and-forge-spike.md`. The Java in Tasks 5 and 7–12 already passed in a throwaway spike against Forge `e8ca48dd`; port it as written and run each task's test.
Blocked on Tanner: nothing for M0–M6. M7 needs `EXPO_TOKEN`, `FLY_API_TOKEN`, an App Store Connect API key, and `ANTHROPIC_API_KEY` (M4 onward).
