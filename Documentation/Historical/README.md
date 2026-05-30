# Historical

This folder holds documentation that is **no longer current** —
superseded design discussions, point-in-time review snapshots, notes on
decisions that have since been revisited, and the like.

Nothing in here should be read as describing the present state of the
codebase. Its purpose is **context**: preserving the reasoning behind
past decisions and changes so a future reader (human or AI) can
understand *why* things ended up the way they are — without that history
cluttering the live documentation in `Documentation/`.

## Conventions

- When a document in `Documentation/` becomes outdated or is replaced,
  **move it here** rather than deleting it. Dating it in the filename is
  encouraged, e.g. `Some design note (2026-05-29).md`, so the snapshot's
  point in time is obvious.
- This is the docs counterpart to `.claude/plans/done/` (completed
  plans).
- Genuinely **transient** scratch files — working notes, question
  trackers, throwaway TODOs — should not be committed at all. They don't
  belong here either; keep them out of version control.
