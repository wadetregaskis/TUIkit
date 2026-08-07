# Reviewing upstream

This fork diverged from [phranck/TUIkit](https://github.com/phranck/TUIkit) at
`6b225313` (2026-04-24) and has since gone a long way its own direction.
Upstream kept moving too. This directory is the standing record of what
upstream did after the fork, what we decided about each change, and what we
did about it.

It exists so that the question "have we looked at that?" always has an answer,
and so the answer survives across sessions, machines, and years.

## What is here

| File | What it holds |
|---|---|
| `ledger.tsv` | One row per upstream commit. The source of truth for position. |
| `notes/PR-NN.md` | The reasoning for one pull request: what it does, what we decided, what we took. |
| `notes/direct.md` | The same, for commits that landed on upstream `main` outside any PR. |
| `open-questions.md` | Items awaiting the owner's decision. Empty is the healthy state. |

Position is *derived* from the ledger, not tracked beside it: "reviewed" means
"has a row". There is deliberately no cursor file, because a cursor and a
ledger can disagree and then neither can be trusted.

## The process

Driven by `Tools/UpstreamReview/upstream-review.sh`:

```bash
Tools/UpstreamReview/upstream-review.sh status
```

1. **Enumerate.** Every upstream-only commit, oldest first, in topological
   order. Topological order matters: it keeps a pull request's commits
   contiguous and places them ahead of the merge that landed them.
2. **Judge with context, not in isolation.** A commit is read against the pull
   request and issue it belongs to. On reaching a PR's first commit, form a
   decision for the whole PR and carry it forward across the rest — but revise
   it if a later commit shows the first read was wrong. Most of upstream's
   commits are intermediate steps inside a PR branch; judged alone, a commit
   like "extract a helper" says nothing.
3. **Act, or ask.** Clear wins are done as part of the review. Anything
   touching public API shape, architecture, or a behaviour judgement goes to
   `open-questions.md` with enough description to decide from.
4. **Record every commit**, including the ones we skip. A verdict of `n-a` is
   as much a result as `adopt`, and recording it is what makes the backlog
   finite.

### Verdicts

| Verdict | Meaning |
|---|---|
| `adopt` | Ported essentially as upstream wrote it. |
| `adapt` | Same intent, reimplemented to fit our diverged foundations. |
| `inspired` | Not ported, but it prompted work here — a test, a check, a fix. |
| `have` | We already have the equivalent, arrived at independently. |
| `n-a` | Does not apply to this fork: their tooling, CI, docs, vendored code. |
| `reject` | Applies, understood, deliberately not wanted here. |
| `defer` | Worth doing, not now. A real backlog item, not a shrug. |
| `queued` | Awaiting the owner's decision — see `open-questions.md`. |
| `noise` | No reviewable content: badge bumps, empty merges, pure formatting. |

The `ours` column carries our own commit hashes for anything we did as a
result, so the ledger reads in both directions: from an upstream change to what
we did, and from one of our commits back to what prompted it.

## Why patches rarely apply

Upstream and this fork now differ by well over a thousand commits. Of the
`Sources/` files upstream has touched since the fork, most still exist here by
path — but their contents have moved a long way. `git cherry-pick` is
therefore the exception, not the rule; `adapt` and `inspired` are the normal
outcomes, and that is not a failure of the process.

Both projects are MIT and `LICENSE` already carries both copyright lines, so
taking code is a matter of judgement rather than permission.

## If upstream rewrites history

The ledger keys on commit hashes, which a force-push destroys. Each row
therefore also carries a `patch_id` — stable across rebases — so an orphaned
row can be re-anchored instead of re-reviewed. `upstream-review.sh verify`
detects the situation and prints the patch id to search by.

`verify` also enforces that the reviewed set is a contiguous *prefix* of the
enumeration. Holes behind the current position would make "where we are"
meaningless, so they are treated as an error rather than a curiosity.

## Scope

The walk covers `upstream/main`. Upstream also has unmerged branches; they are
not part of the numbered backlog and are tracked at the bottom of
`open-questions.md`, because an unmerged branch is a proposal rather than a
decision and may still change under us.
