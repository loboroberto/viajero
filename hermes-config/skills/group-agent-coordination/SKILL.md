---
name: group-agent-coordination
description: >
  Use whenever you operate in a channel where other independent agents are
  present — GitHub PR threads, project boards, paperclip_ai / multica
  coordination spaces, or any [[channels.channel]] with kind ∈
  {peer-agent, group, broadcast}. Enumerates the five coordination
  primitives (discovery, claim, release, hand-off, defer, escalate) and
  how each realizes per channel kind. Trigger phrases: peer agent, group
  channel, claim, hand off, who's working on, are we stepping on, multi
  agent, coordinate with.
version: 1.0.0
tags: [coala, meta, group, multi-agent, coordination]
---

# Group-Agent Coordination (CoALA §4.2 dialogue, §4.6 in groups)

The meta-skill for participating coherently in a group of independent
agents. Your local decision cycle still owns your behavior; this skill
constrains how Propose, Select, and Execute change when the group's
shared state is on the table.

## When to Use

Any cycle where the relevant channel has `kind` ∈ `{peer-agent, group,
broadcast}` in `hermes-config/hermes.toml [[channels.channel]]`. Also:

- You're about to fire a grounding action on a shared surface (a PR
  comment, an issue close, a project-board move).
- You observed a peer's action and need to decide whether to react,
  defer, or ignore.
- A user request implies coordination ("see if @peer-x has this", "take
  over from the bot", "make sure we don't double up").

## Pre-Flight (do once per channel-entry)

1. **Retrieve** (CoALA §4.3):
   - `PEERS.md` — who are the registered peers?
   - `hermes.toml [[channels.channel]]` for the active channel — `kind`,
     `visibility`, `etiquette`.
   - Recent channel history (last N messages / commits / events) via the
     channel's transport — what's already been claimed or done?
2. **Observe** (CoALA §4.1): name the peers currently active in this
   channel and any open claims you can see. Write a one-line summary
   into working memory: *"Channel X (kind=group). Peers active: A, B.
   Open claims: A holds #142; B mid-review on PR #87."*
3. If `PEERS.md` is missing an active peer, that's a learning candidate
   for end-of-cycle (don't write mid-cycle).

## The Six Primitives

Each is a specific grounding-action shape. The CoALA type is always
GROUNDING (dialogue sub-kind). Per-channel realization varies.

### Discovery
Read who is present and what is claimed. Always the first cycle in a
new channel; refresh whenever you've been away.

| Channel kind     | Realization                                            |
|------------------|--------------------------------------------------------|
| GitHub issue/PR  | List assignees, reviewers, recent comments. Read draft/ready state. |
| GitHub project   | List board columns + cards + assignees.                |
| paperclip_ai     | Query the platform's agent-presence endpoint.          |
| multica          | Subscribe to the swarm-state stream.                   |
| Free-form chat   | Scan last N messages for `@`-mentions and claim verbs. |

### Claim
Announce intent to work on a specific item. Becomes a constraint on
every peer's subsequent Propose. **Always observable** — a silent
claim is not a claim.

| Channel kind     | Realization                                            |
|------------------|--------------------------------------------------------|
| GitHub issue     | Self-assign the issue.                                 |
| GitHub PR        | Open as draft; the draft state *is* the claim.         |
| GitHub project   | Move card to "In progress" + self-assign.              |
| paperclip_ai     | `claim` message addressed to the coordinator.          |
| multica          | Broadcast `intent` event with item ID.                 |
| Free-form chat   | Explicit "I'm taking X" message, anchored to item ID.  |

### Release
End a claim explicitly. **Required** when a peer might be blocked on
you — silent release is also a defection.

| Channel kind     | Realization                                            |
|------------------|--------------------------------------------------------|
| GitHub issue     | Unassign self; comment why if non-obvious.             |
| GitHub PR        | Close as not-going-forward or convert back to draft.   |
| GitHub project   | Move card back to "Ready" + unassign.                  |
| paperclip_ai     | `release` message with item ID + reason.               |
| multica          | Broadcast `release` event.                             |
| Free-form chat   | "Dropping X — over to whoever wants it."               |

### Hand-Off
Transfer ownership with the context the next agent needs. Combines a
release with a directed claim invitation.

| Channel kind     | Realization                                            |
|------------------|--------------------------------------------------------|
| GitHub PR        | Convert to ready + request review from named peer + comment summarizing state. |
| GitHub project   | Move card to "Needs review" + assign named peer.       |
| paperclip_ai     | `handoff` message naming recipient + context payload.  |
| multica          | `handoff` event with recipient ID.                     |
| Free-form chat   | "@peer-x, picking up from <link>; remaining: …"        |

### Defer
Yield to a peer who has higher trust or better context. Cheap;
prevents duplicate work. **Default move** when a relevant peer claim
exists and you have no reason to override.

| Channel kind     | Realization                                            |
|------------------|--------------------------------------------------------|
| Any              | Do not act on the item. Optionally post a one-line "deferring to @peer-x on this." |

### Escalate
Surface a conflict to the human operator when two agents have
contradictory claims and neither can yield. Last resort.

| Channel kind     | Realization                                            |
|------------------|--------------------------------------------------------|
| Any              | Post a structured escalation: who, what conflict, what each agent proposes, what input is needed. Cc the operator's primary channel. |

## Procedure (per cycle, in group channel)

1. **Pre-flight** as above (skip if you entered this channel earlier
   this session and nothing's changed).
2. **Propose** (CoALA §4.6) — for each candidate action, list peer
   claims it touches. A candidate that silently overlaps a peer claim
   is not a valid candidate; the only valid moves on it are *defer*,
   *negotiate*, or *escalate*.
3. **Evaluate** — apply the standard four criteria plus **group
   coherence**: does this keep the shared state consistent?
4. **Select** — when in doubt, defer. The cost of deferring once is
   small; the cost of duplicate work compounds with every cycle.
5. **Execute** — fire the primitive. Use the channel's native
   realization (see tables above). Attribute yourself by ID; never
   anonymously.
6. **Learn** (optional) — if you observed a durable fact about a peer
   (new capability, repeated failure mode, change in trust), write to
   `PEERS.md`. Spurious learning here is especially harmful — it
   poisons future Propose phases.

## Pitfalls

- **Silent claim-stepping.** Acting on an item a peer has claimed without
  acknowledging the claim. Even if your action would have been better,
  the group's shared state is now incoherent.
- **Broadcasting a private finding.** A fact you learned in a private
  user-dialogue channel does not automatically belong in a public group
  channel. If you surface it, name the reason.
- **Assuming async = consent.** "Nobody objected in 10 minutes" is not
  consent on an async channel. Peers may not have observed the message
  yet. Wait, or escalate, or proceed and own the consequence — but
  don't pretend you got consent.
- **Collapsing peer identities.** "The other agents agreed" is a lie if
  one specific peer agreed and two never observed. Name peers.
- **Re-deriving instead of asking.** If a peer holds context you don't
  have, ask them via the channel before re-doing their analysis.

## Verification

A well-coordinated cycle leaves a transcript where:

- The channel ID and kind are named in your Observe.
- Any peer claim you touched is named, with the resolution (defer /
  negotiate / override-with-reason).
- The primitive you fired (claim / release / hand-off / etc.) is named
  by name.
- Your action is attributed to you by ID (the peer-visible name from
  `PEERS.md` or your agent ID).
- If you wrote to `PEERS.md`, the entry cites the episode that
  produced it.
