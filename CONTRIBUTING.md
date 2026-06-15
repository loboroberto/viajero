# Contributing

This repository is the **CoALA-aligned substrate** (`hermes-interprets-coala`). It is
consumed by downstream deployments that materialize this substrate into their own
image/runtime — typically by pinning a substrate release tag and bumping it to adopt changes.

Because work flows in one direction (substrate → consumers), **it matters that every issue
and PR lands in the repo that owns the layer it changes.** Substrate work done in a consumer's
repo can't propagate back up to other consumers; consumer-specific operationalization done
here pollutes the shared substrate.

## Where does this issue/PR go?

- **Does it touch the CoALA substrate?** — `AGENTS.md`, `SOUL.md`, `hermes.toml`,
  `mcp.json`, the seed `skills/`, the decision-cycle / cognitive model, or any Hermes
  capability that *any* consumer of the substrate would want.
  → **This repo.** After it lands, it is tagged `vYYYY.M.D`; consumers adopt it by bumping
  the substrate release they pin.

- **Does it operationalize the substrate for one deployment?** — runner/host wiring, fleet
  orchestration, environment/secrets, or the image/build that composes this substrate into a
  running service.
  → **That consumer's own repo**, not here.

- **Unsure, or it spans both?** → file it where the *larger* half lives, label it
  `scope: needs-triage`, and call out the cross-layer part so it can be split. A consumer-side
  issue whose real fix is in the substrate should spawn a separate issue here rather than being
  worked around downstream.

## Scope labels

Every issue carries exactly one `scope:` label so its correct home is unambiguous:

| Label | Meaning |
|-------|---------|
| `scope: upstream` | Belongs in this substrate repo. |
| `scope: downstream` | Operationalization — belongs in a consumer's repo, not the substrate. |
| `scope: needs-triage` | Layer not yet determined — **do not implement until resolved.** |

If an issue is filed in the wrong place, maintainers relabel it and transfer it
(`gh issue transfer <n> <dest-repo>`). The scope labels exist here — and in consumer repos
that adopt the convention — so they survive the transfer.

The **New issue** chooser is wired to this boundary: the substrate template pre-applies
`scope: upstream`, and a contact link points operationalization work back to the consumer
that owns it.
