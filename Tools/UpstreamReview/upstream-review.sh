#!/usr/bin/env bash
#
# upstream-review.sh — enumerate, position, and audit the review of upstream
# (phranck/TUIkit) commits against this fork.
#
# The fork carries well over a thousand commits of divergence, so upstream
# changes are almost never applied as patches; they are read, judged, and where
# valuable ported or reimplemented. That judgement is a human/agent activity.
# This script does the parts that must be mechanical and repeatable:
#
#   - enumerate EVERY upstream commit since the fork point, oldest first, in a
#     deterministic order that keeps each pull request's commits together;
#   - attribute each commit to the pull request that brought it in, so a commit
#     can be judged with the feature it belongs to rather than in isolation;
#   - remember how far the review has got, by reading the ledger rather than by
#     keeping separate state that could disagree with it;
#   - verify the ledger has not drifted from upstream's history.
#
# The ledger is Documentation/Upstream-review/ledger.tsv. It is the single
# source of truth for position: "reviewed so far" is exactly "recorded there".
# There is no cursor file to fall out of sync with it.
#
# Usage:
#   Tools/UpstreamReview/upstream-review.sh status        # where we are
#   Tools/UpstreamReview/upstream-review.sh next [N]      # next N to review
#   Tools/UpstreamReview/upstream-review.sh show <sha>    # one commit + its PR
#   Tools/UpstreamReview/upstream-review.sh pr <N>        # every commit of a PR
#   Tools/UpstreamReview/upstream-review.sh record <sha> <verdict> <ours> <note>
#   Tools/UpstreamReview/upstream-review.sh verify        # ledger integrity
#   Tools/UpstreamReview/upstream-review.sh fetch         # git fetch upstream
#
# `record` appends one row; `ours` is a comma-separated list of OUR commit
# hashes (or "-"). Verdicts are checked against the vocabulary below, so a typo
# cannot quietly invent a new category.
#
# Exit status: 0 on success, 1 on a usage error or a failed verification.
#
# Bash 3.2 compatible (macOS ships 3.2) — no associative arrays, no mapfile.

set -euo pipefail
cd "$(dirname "$0")/../.."

LEDGER="Documentation/Upstream-review/ledger.tsv"
UPSTREAM_REF="upstream/main"

# The controlled vocabulary. Anything outside this is rejected by `record`.
#
#   adopt    ported into our tree essentially as upstream wrote it
#   adapt    the same intent, reimplemented to fit our diverged foundations
#   inspired did not port it, but it prompted work here (a test, a check, a fix)
#   have     we already have the equivalent, arrived at independently
#   n-a      does not apply to this fork (their tooling, CI, docs, vendored code)
#   reject   applies, understood, deliberately not wanted here
#   defer    worth doing, not now — a real backlog item, not a shrug
#   queued   awaiting the owner's decision (see open-questions.md)
#   noise    no reviewable content (badge bumps, empty merges, pure formatting)
VERDICTS="adopt adapt inspired have n-a reject defer queued noise"

die() { printf 'error: %s\n' "$1" >&2; exit 1; }

base_commit() {
    git merge-base HEAD "$UPSTREAM_REF" 2>/dev/null \
        || die "no merge base with $UPSTREAM_REF — is the 'upstream' remote configured and fetched?"
}

# Every upstream-only commit, oldest first, in topological order. Topological
# order is what keeps a pull request's commits contiguous and ahead of the merge
# that landed them, which is what lets a decision be made once per PR and then
# carried forward across its commits.
ordered_commits() {
    git rev-list --reverse --topo-order "$(base_commit)..$UPSTREAM_REF"
}

# Print "<sha> <pr>" for every upstream-only commit. A commit's PR is the pull
# request whose merge introduced it; commits that landed directly on main get
# "-". Merge commits are attributed to their own PR.
#
# Recomputed on demand rather than cached: a cache would be one more thing that
# could disagree with the history it describes.
pr_map() {
    local base merge pr side
    base="$(base_commit)"
    git rev-list --merges "$base..$UPSTREAM_REF" | while read -r merge; do
        pr="$(git log -1 --format='%s' "$merge" \
            | sed -n 's/^Merge pull request #\([0-9][0-9]*\).*/\1/p')"
        [ -n "$pr" ] || pr="?"
        printf '%s\t%s\n' "$merge" "$pr"
        # ^1..^2 is the side branch: the commits this merge brought in that were
        # not already on the receiving side.
        git rev-list "$merge^1..$merge^2" 2>/dev/null | while read -r side; do
            printf '%s\t%s\n' "$side" "$pr"
        done
    done
}

# pr_map keys on full hashes, so resolve whatever the caller passed (short hash,
# tag, HEAD~3) before looking it up — an unresolved short hash silently misses
# and every commit would look like it landed outside a PR.
pr_of() {
    local sha
    sha="$(git rev-parse "$1")"
    # `awk … exit` stops reading as soon as it has the answer, which leaves
    # pr_map writing into a closed pipe: SIGPIPE, 141, and under `pipefail` an
    # abort. How early awk stops depends on where the commit sits in pr_map's
    # output, so the same call succeeded or died depending on which commit it
    # was asked about. Run the pipeline where pipefail cannot see it.
    (
        set +o pipefail
        pr_map | awk -v s="$sha" '
            $1 == s { print $2; found = 1; exit }
            END { if (!found) print "-" }'
    )
}

# Commits already recorded, one hash per line.
reviewed_shas() {
    [ -f "$LEDGER" ] || return 0
    awk -F'\t' 'NR > 1 && $2 != "" { print $2 }' "$LEDGER"
}

# The patch id is a convenience for re-anchoring a row after upstream rebases,
# never load-bearing — so this must not be able to abort a recording.
#
# It could, before this: `git patch-id` stops reading once it has hashed what it
# needs, `git show` then takes SIGPIPE writing the rest, and under `pipefail`
# that is a 141 exit that `set -e` turns into a silent abort. Large commits hit
# it and small ones did not, so seven rows of a batch vanished without a word.
patch_id_of() {
    (
        set +o pipefail
        git show "$1" 2>/dev/null | git patch-id --stable 2>/dev/null | cut -c1-12
    ) || true
}

cmd_fetch() {
    git fetch upstream
    printf 'upstream/main is now %s\n' "$(git log -1 --format='%h %ad %s' --date=short "$UPSTREAM_REF")"
}

cmd_status() {
    local base total done_count remaining next
    base="$(base_commit)"
    total="$(ordered_commits | wc -l | tr -d ' ')"
    done_count="$(reviewed_shas | wc -l | tr -d ' ')"
    remaining=$((total - done_count))

    printf 'fork point   %s\n' "$(git log -1 --format='%h %ad %s' --date=short "$base")"
    printf 'upstream     %s\n' "$(git log -1 --format='%h %ad %s' --date=short "$UPSTREAM_REF")"
    printf 'commits      %d total, %d reviewed, %d remaining\n' "$total" "$done_count" "$remaining"

    if [ -f "$LEDGER" ] && [ "$done_count" -gt 0 ]; then
        printf 'last review  %s\n' "$(tail -1 "$LEDGER" | cut -f2,4,8 | tr '\t' ' ')"
        printf 'verdicts     '
        awk -F'\t' 'NR > 1 { c[$6]++ } END { for (v in c) printf "%s=%d ", v, c[v]; print "" }' "$LEDGER"
    fi

    if [ "$remaining" -gt 0 ]; then
        next="$(cmd_next 1 | tail -1)"
        printf 'next up      %s\n' "$next"
    else
        printf 'next up      — backlog clear\n'
    fi
}

# The next N unreviewed commits, oldest first, with their PR attribution.
cmd_next() {
    local count="${1:-20}" tmp_reviewed tmp_prs
    tmp_reviewed="$(mktemp)"; tmp_prs="$(mktemp)"
    trap 'rm -f "$tmp_reviewed" "$tmp_prs"' RETURN
    reviewed_shas | sort > "$tmp_reviewed"
    pr_map > "$tmp_prs"

    local seq=0 sha short pr
    while read -r sha; do
        seq=$((seq + 1))
        short="$(git rev-parse --short=12 "$sha")"
        grep -qx "$short" "$tmp_reviewed" && continue
        pr="$(awk -v s="$sha" '$1 == s { print $2; exit }' "$tmp_prs")"
        [ -n "$pr" ] || pr="-"
        printf '%4d  %s  %s  PR%-4s %s\n' \
            "$seq" "$short" "$(git log -1 --format='%ad' --date=short "$sha")" \
            "$pr" "$(git log -1 --format='%s' "$sha")"
        count=$((count - 1))
        [ "$count" -le 0 ] && break
    done < <(ordered_commits)
}

cmd_show() {
    local sha="${1:?usage: show <sha>}" pr
    pr="$(pr_of "$sha")"
    printf '=== commit %s  (PR %s)\n' "$(git rev-parse --short=12 "$sha")" "$pr"
    git log -1 --format='%an <%ae>  %ad%n%n%B' --date=short "$sha"
    printf '=== files\n'
    git show --stat --format='' "$sha"
    printf '=== patch\n'
    git show --format='' "$sha"
}

cmd_pr() {
    local pr="${1:?usage: pr <number>}"
    printf '=== PR #%s commits (oldest first)\n' "$pr"
    pr_map | awk -F'\t' -v p="$pr" '$2 == p { print $1 }' > /tmp/.upstream-pr-shas.$$
    local sha
    while read -r sha; do
        git log -1 --format='%h %ad %s' --date=short "$sha"
    done < <(ordered_commits | grep -F -f /tmp/.upstream-pr-shas.$$ || true)
    rm -f /tmp/.upstream-pr-shas.$$
}

cmd_record() {
    local sha="${1:?usage: record <sha> <verdict> <ours> <note>}"
    local verdict="${2:?missing verdict}" ours="${3:--}" note="${4:-}"
    local short pid pr seq

    case " $VERDICTS " in
        *" $verdict "*) ;;
        *) die "unknown verdict '$verdict' (expected one of: $VERDICTS)" ;;
    esac

    short="$(git rev-parse --short=12 "$sha")" || die "unknown commit $sha"
    reviewed_shas | grep -qx "$short" && die "$short is already in the ledger"

    seq="$(ordered_commits | grep -n "^$(git rev-parse "$sha")$" | cut -d: -f1)"
    [ -n "$seq" ] || die "$short is not an upstream-only commit"
    pid="$(patch_id_of "$sha")"
    pr="$(pr_of "$sha")"

    [ -f "$LEDGER" ] || printf 'seq\tsha\tpatch_id\tdate\tpr\tverdict\tours\tsubject\n' > "$LEDGER"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$seq" "$short" "${pid:--}" \
        "$(git log -1 --format='%ad' --date=short "$sha")" \
        "$pr" "$verdict" "${ours:--}" \
        "$(git log -1 --format='%s' "$sha" | tr '\t' ' ')" >> "$LEDGER"
    [ -n "$note" ] && printf 'note: %s\n' "$note"
    printf 'recorded %s (%s)\n' "$short" "$verdict"
}

# Integrity. Four ways the ledger can go wrong, each checked:
#   1. it names a commit upstream no longer has (a force-push or rebase);
#   2. it names the same commit twice;
#   3. it skips a commit — the reviewed set must be a PREFIX of the enumeration,
#      because "where we are" is meaningless if there are holes behind us;
#   4. a verdict outside the vocabulary.
#
# For (1) the patch_id column is the recovery route: a rebased commit keeps its
# patch id, so an orphaned row can be re-anchored rather than re-reviewed.
cmd_verify() {
    local failures=0 tmp_order tmp_reviewed
    [ -f "$LEDGER" ] || { printf 'no ledger yet — nothing to verify\n'; return 0; }

    tmp_order="$(mktemp)"; tmp_reviewed="$(mktemp)"
    trap 'rm -f "$tmp_order" "$tmp_reviewed"' RETURN
    ordered_commits | while read -r c; do git rev-parse --short=12 "$c"; done > "$tmp_order"
    reviewed_shas > "$tmp_reviewed"

    local sha
    while read -r sha; do
        grep -qx "$sha" "$tmp_order" || {
            printf 'ORPHAN   %s is in the ledger but not in %s\n' "$sha" "$UPSTREAM_REF"
            printf '         re-anchor by patch id: %s\n' \
                "$(awk -F'\t' -v s="$sha" '$2 == s { print $3 }' "$LEDGER")"
            failures=$((failures + 1))
        }
    done < "$tmp_reviewed"

    local dupes
    dupes="$(sort "$tmp_reviewed" | uniq -d)"
    [ -n "$dupes" ] && {
        printf 'DUPLICATE %s\n' $dupes
        failures=$((failures + 1))
    }

    # Prefix check: the first N enumerated commits must be exactly the reviewed
    # set, in order.
    local n
    n="$(wc -l < "$tmp_reviewed" | tr -d ' ')"
    if [ "$n" -gt 0 ]; then
        if ! diff -q <(head -n "$n" "$tmp_order") <(cut -f2 "$LEDGER" | tail -n +2) >/dev/null 2>&1; then
            printf 'GAP      the reviewed set is not a contiguous prefix of upstream order\n'
            printf '         (first divergence)\n'
            diff <(head -n "$n" "$tmp_order") <(cut -f2 "$LEDGER" | tail -n +2) | head -6
            failures=$((failures + 1))
        fi
    fi

    local v
    while read -r v; do
        case " $VERDICTS " in
            *" $v "*) ;;
            *) printf 'BAD VERDICT %s\n' "$v"; failures=$((failures + 1)) ;;
        esac
    done < <(awk -F'\t' 'NR > 1 { print $6 }' "$LEDGER" | sort -u)

    if [ "$failures" -eq 0 ]; then
        printf 'ledger OK: %d commits recorded, contiguous, all reachable\n' "$n"
        return 0
    fi
    printf '%d problem(s)\n' "$failures"
    return 1
}

case "${1:-status}" in
    fetch) cmd_fetch ;;
    status) cmd_status ;;
    next) shift; cmd_next "$@" ;;
    show) shift; cmd_show "$@" ;;
    pr) shift; cmd_pr "$@" ;;
    record) shift; cmd_record "$@" ;;
    verify) cmd_verify ;;
    *) die "unknown command '$1' (status|next|show|pr|record|verify|fetch)" ;;
esac
