---
name: github-projects-ops
description: >
  Use when the agent needs to operate on GitHub at the repo/org level —
  issues, project boards, milestones, PR participation, releases, labels.
  Covers the actual primitives the GitHub MCP exposes plus the etiquette
  that keeps you from being That Bot in the thread. Pairs with the
  `group-agent-coordination` meta-skill: this skill is the *how*, that
  skill is the *whether*. Trigger phrases: github issue, github pr,
  project board, milestone, label, triage, open issue, close issue,
  request review, assign, gh.
version: 1.0.0
tags: [github, domain, group, peers, mcp]
---

# GitHub Projects, Issues, Milestones, PRs

Concrete how-to for the `github` MCP server (see `mcp.json` and
`hermes.toml [[channels.channel]]` entries with `transport_ref =
"github"`). The MCP exposes most of what the REST API exposes; this
skill is about *which calls in what order* and *how not to make peers
miserable*.

## Prerequisites

- `GITHUB_TOKEN` env var set, with at least `repo` + `read:project` +
  `project` (write) scopes for the target repos.
- The `github` entry in `mcp.json` is active (no underscore prefix).
- You know which repo(s) you're authorized to act on. **Default to
  read-only on any repo you haven't been explicitly told you can
  write to.**

## Channels This Skill Serves

From `hermes.toml`:

- `github-issue` (kind=group, visibility=public)
- `github-pr-comments` (kind=group, visibility=public)
- `github-project-events` (kind=broadcast, visibility=public)

Always consult `group-agent-coordination` before firing a write on any
of these. They are **public, async, non-reversible** — a posted comment
that a peer has observed cannot be unposted.

## Issues

### Triage
1. **Read first.** Fetch the issue body + all comments + current
   labels/assignees/milestone. Don't act on title alone.
2. **Classify.** Pick from the repo's existing label set; don't invent
   new labels (that's an architectural change requiring user approval).
3. **Apply labels** in one call if possible; multiple label-add calls
   spam the activity feed.
4. **Assign carefully.** Self-assigning is a claim (see
   `group-agent-coordination`). Don't assign humans without their
   prior consent.

### Opening
- Title: imperative, ≤72 chars, no period at end.
- Body: problem → repro (if bug) → expected vs. actual → environment.
  Link any related issue/PR with `#NNN`.
- Add labels you're confident about; leave the rest for a human triager.
- If you're opening it as a claim ("I'm doing this"), also self-assign
  in the same call.

### Closing
- Never close an issue you didn't open or weren't assigned without an
  explicit reason in the close comment.
- Link the resolving PR (`Closes #NNN` in the PR body usually handles
  this automatically — check first).
- Don't close as `not planned` without naming who decided that and why.

## Project Boards (Projects v2)

### Card moves
- Read the board's column structure before moving anything. Don't
  assume the canonical `Todo → In Progress → Done` triplet — many
  boards have `Blocked`, `Needs Review`, `Released`, etc.
- Moving a card is a state change visible to every watcher. Batch
  related moves into the same cycle when possible.
- **Claim**: move to `In Progress` + self-assign. **Hand-off**: move
  to `Needs Review` + assign next agent. **Release**: move back to
  `Ready` + unassign.

### Custom fields
- Read the field schema before writing. Required fields differ per
  project.
- Iteration / Sprint fields: assign only if you know the current
  iteration. Otherwise leave blank and flag.

## Milestones

- **Hygiene cycle**: when a milestone's due date is within 48h, scan
  for issues still open and report (don't reassign or move dates
  unilaterally — that's an escalation to the human).
- Don't move issues between milestones without naming why in a comment.
- A milestone with 0 open issues + 100% checked-off is shippable;
  flag it in the project's broadcast channel.

## Pull Requests

### Opening
1. **Always open as DRAFT.** The draft state is your claim (see
   `group-agent-coordination`); ready-for-review is your hand-off.
2. **Title**: `<scope>: <imperative verb-phrase>` (e.g., `auth: drop
   unused refresh-token middleware`).
3. **Body** sections: *Why*, *What changed* (1-2 bullets), *How to
   verify*, *Risks/rollback*. Link the issue: `Closes #NNN`.
4. **Self-link evidence**: paste the failing test output, the log line,
   the screenshot — whatever grounds the change.

### Requesting review
- Wait until CI is green. Requesting review on red CI burns peer time.
- Request from the **one** person most affected by this change. Mass
  review requests are a smell.
- If a `CODEOWNERS` rule covers the file, the requested reviewer is
  already implied — don't double-add.

### Reviewing
- **Never approve your own PR.** Not even via a second account.
- One **substantive** comment > five nitpicks. If the design is wrong,
  say so once and link to a discussion thread; don't litter the diff
  with line comments first.
- Use `Request changes` only when something is actually wrong, not when
  you have suggestions. Suggestions go in `Comment`.
- When you `Approve`, you are claiming responsibility for what ships.
  Don't approve on a glance.

### Closing
- Don't merge a peer's PR without their assent unless you have explicit
  authorization. Auto-merge labels are the agreed-on mechanism for
  that.
- After merge, post a one-line "merged at <sha>" only if the channel
  expects it (some teams have bots that already announce). Otherwise
  silence is fine.

## Comments — etiquette

- **Link evidence.** Every claim of "this is broken" or "this works"
  links to a line, log, or test result.
- **Attribute peers.** "@peer-x's earlier point about the migration
  race is the blocker here" — not "as discussed above."
- **No chatter on closed threads.** A closed issue is a closed issue.
  If you need to reopen the discussion, open a new issue and link
  back.
- **One substantive thought per comment.** Don't braindump.
- **Quote-reply when responding to a specific peer.** GitHub's quote
  shows attribution.

## Releases

- Tag format: follow the repo's existing convention. Read recent tags
  first.
- Release notes: aggregate from merged PR titles since last tag. Group
  by label (feat / fix / chore). Always credit each PR author by `@`.
- Don't publish a release on a branch that hasn't been promoted to
  the release-tracking branch (usually `main`).

## Pitfalls

- **Mass-labeling sweeps.** Don't label-bombing every open issue. The
  notification storm punishes every subscriber.
- **Stale-bot behavior.** Closing inactive issues without context is
  net-negative. Get explicit authorization before any "stale" sweep.
- **Cross-org actions.** You probably don't have rights, and even if
  you do, your authorization scope likely doesn't cover it.
- **Force-pushing to a branch with an open PR.** Destroys review
  history. Use new commits instead unless explicitly authorized.

## Verification

After firing a write action:

1. Re-fetch the affected resource (issue / PR / card) and confirm the
   change took effect.
2. Confirm the activity feed entry attributes the action to your bot
   identity (not anonymously, not as a human).
3. If the action was a claim/release/hand-off, confirm the
   corresponding state is observable to peers (assignee shown, label
   visible, card moved).
4. Episodic write: log the action with item ID, channel ID, and
   outcome.
