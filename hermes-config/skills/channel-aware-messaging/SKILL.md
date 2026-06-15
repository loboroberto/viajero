---
name: channel-aware-messaging
description: >
  Use whenever you're about to compose an outbound message and have a
  choice of channel — DM the user, post in a PR thread, broadcast in a
  multi-agent coordination space, etc. Picks the right channel from the
  `hermes.toml [[channels.channel]]` registry, respects each channel's
  etiquette tag, and guards against visibility escalation (private →
  public without a reason). Trigger phrases: where should I post, which
  channel, broadcast this, ping the team, reply to, dm them, public or
  private, share this with.
version: 1.0.0
tags: [meta, channels, group, etiquette]
---

# Channel-Aware Messaging (CoALA §4.2 dialogue, §6.2 channel discipline)

The meta-skill for choosing **where** an outbound message goes, and
adapting its shape to the channel's rules. Always consult before any
dialogue grounding action where you have a real choice of surface.

## When to Use

- You composed (or are about to compose) a message and there's more
  than one plausible channel for it.
- You're considering surfacing a finding from a private channel into a
  public one.
- A peer pinged you in channel A and you'd naturally reply in channel
  B (e.g., they messaged in chat and you want to reply in a PR
  comment).
- You're about to send a notification, broadcast, or status update.

If there's exactly one obviously-correct channel (e.g., the user just
asked you something in DM), this skill is overhead — say so and reply
in place.

## The Decision

Three questions, in order. Answer each from the channel registry
(`hermes.toml [[channels.channel]]`), not from intuition.

### 1. Who needs to see this?

- **Just the user** → `kind=human` channel, usually `visibility=private`.
- **A specific peer** → `kind=peer-agent` channel for that peer if one
  exists, otherwise `@`-mention them in the most relevant `kind=group`
  channel.
- **A coordinating group (humans + peers)** → `kind=group`.
- **Everyone subscribed to this topic, for awareness only** →
  `kind=broadcast`. Use sparingly.

### 2. Does this need a reply, or is it FYI?

- Reply expected → prefer a `sync` channel if one exists; otherwise an
  `async` channel with an explicit prompt ("@peer-x, decision needed
  on X").
- FYI / status → `async` is fine. Label it `[FYI]` so peers can
  deprioritize.

### 3. Does the channel's `etiquette` tag fit?

Read the channel's `etiquette` field. Common tags and what they mean:

| Tag                       | Means                                                      |
|---------------------------|------------------------------------------------------------|
| `terse`                   | One sentence or less. No preamble.                         |
| `formal`                  | Full grammar, attribution, no jargon-only shorthand.       |
| `link-evidence`           | Every claim links to its source (log line, test, PR).      |
| `attribute-peers`         | Name the peer whose work or claim you're responding to.    |
| `no-chatter-on-closed`    | Don't post on items in a closed/resolved state.            |
| `one-substantive-comment` | One thought per post; don't accumulate nitpicks.           |
| `never-approve-own`       | Don't approve / merge / mark-done your own item.           |
| `state-change-only`       | Post when state changes; never narrate inflight reasoning. |
| `link-line`               | Anchor to a file:line, not the whole diff.                 |
| `claim-on-entry`          | First message when entering must announce intent.          |
| `structured`              | Use the channel's expected schema (often JSON / form-fields). |
| `one-decision-per-message`| Don't bundle decisions; broadcast subscribers can't unbundle. |

If your message doesn't fit the tag, **reshape the message**, don't
override the tag.

## Composition Rules

After picking a channel:

1. **Lead with the audience signal.** `[FYI]`, `[Decision needed]`,
   `[Question for @peer-x]`, `[Status]`, `[Claim]`, `[Release]`. Async
   channels especially need this so peers can prioritize without reading
   the body.
2. **Attribute yourself.** Your bot identity (from `PEERS.md` as the
   peers see you) is on every message; never anonymous.
3. **Quote or link the antecedent** when replying. Group channels lose
   context fast.
4. **One message per cycle output.** If you have two distinct things
   to say, that's two channels' worth of decisions — make them
   separately.

## Visibility Escalation Guard

Moving content from `visibility=private` to `visibility=public` is a
distinct decision that requires explicit reasoning. Before doing it:

1. State the **reason** for surfacing. ("The user authorized me to
   share this." / "The peer needs this to unblock #142." / "This is a
   safety concern that affects the group.")
2. **Sanitize.** Strip user-identifying details that don't need to
   travel with the substance. Strip credentials, internal URLs, prior
   unrelated context.
3. **Reframe for the new audience.** A finding written for the user
   ("you mentioned earlier that…") needs rewriting for a group
   ("@user observed earlier that…").
4. **Log the escalation** as an episode. Surface-events are auditable.

The reverse — moving public content into private — is cheap and almost
always fine. No guard needed.

## Reply Routing

When pinged in channel A but the natural reply belongs in channel B:

1. **Default**: reply in A first ("see channel B for the substantive
   reply: <link>") then post the substance in B.
2. **Exception**: if A is a public broadcast and B is a focused work
   channel, route silently — don't pollute A with meta-chatter about
   where the reply went.

## Threading

- **Reply in thread > new thread.** Always. Top-level posting
  fragments the conversation and breaks every subscriber's history.
- **New thread** is justified only when: (a) the topic genuinely
  diverges, or (b) the parent thread is closed/archived.
- On channels without threading, use a quote-reply to anchor.

## Pitfalls

- **Channel-shopping**. Picking a quieter channel because a peer might
  push back on the message in the louder one. If the message wouldn't
  survive scrutiny in the right channel, the message is wrong, not the
  channel.
- **Cross-posting**. Saying the same thing in three channels for
  visibility is noise. Pick one and `@`-mention the others if needed.
- **Etiquette drift**. Channels accumulate norms over time that aren't
  in the `etiquette` tag yet. Read recent history; if the norm has
  drifted, propose updating the tag rather than silently following
  drift.
- **Assuming reach**. A message in a `kind=broadcast` channel does not
  guarantee any specific peer saw it. If you need a peer to act,
  address them directly.

## Verification

A well-routed message leaves a transcript where:

- The chosen channel ID is stated in the cycle's Observe / Plan.
- The etiquette tag was named and obeyed.
- If visibility escalated, the reason is logged.
- The message has an audience signal in its first ~80 characters.
- You attributed yourself, and attributed any peer you cited.
