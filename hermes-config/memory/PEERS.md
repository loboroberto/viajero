# PEERS.md — Peer Agent Model

Semantic memory (CoALA §4.1, §4.5) for other agents this deployment shares work
with. Parallel to `USER.md` but for non-human collaborators. See AGENTS.md §6.

This agent serves **one principal traveler** and has no peer agents by default. If
the principal's setup later requires multi-agent coordination (e.g. a shared
flight-tracking agent, an expense-review agent), model each peer here: identity,
declared capabilities, observed behavior, trust level, characteristic failure modes,
and which channels they monitor. Updated by direct principal instruction, by the
`coala-reflection` skill, and by the `group-agent-coordination` skill when a cycle
produces a durable fact about a peer.

Peers declared in `mcp.json` / integration config are the *declaration*; this file is
the *experience-grounded* model. They drift apart over time — that's expected.
Reconcile during reflection.

## Format
```
## <peer-id>
- Declared capabilities: ...
- Observed behavior: ...
- Trust: untrusted | scoped | trusted
- Channels: <ids of channels where this peer is active>
- Notable episodes: <episode refs or dates>
```

_(empty — populated as the agent collaborates)_
