# Contributing

This repository is the **upstream CoALA-aligned substrate** (`hermes-interprets-coala`).
It is consumed by downstream deployments — notably
[`hcoala-in-paperclip`](https://github.com/loboroboto/hcoala-in-paperclip), which
materializes this substrate into its image at build time via a pinned `HCOALA_REF`.

Because work flows in one direction (substrate → consumers), **it matters that every
issue and PR lands in the repo that owns the layer it changes.** Substrate work done
in a downstream repo can't propagate back up; downstream operationalization done here
pollutes the shared substrate.

## Where does this issue/PR go?

Apply this test — it is identical in both repos:

- **Does it touch the CoALA substrate?** — `AGENTS.md`, `SOUL.md`, `hermes.toml`,
  `mcp.json`, the seed `skills/`, the decision-cycle / cognitive model, or any Hermes
  capability that *any* consumer of the substrate would want.
  → **Upstream** — `hermes-interprets-coala` (**this repo**). After it lands, tag
  `vYYYY.M.D` and consumers bump their `HCOALA_REF` to pull it.

- **Does it touch Paperclip operationalization?** — the composing Dockerfile, the
  `paperclip-hermes-gateway` runner, the onboarder/reconciler, `fleet/agents.yaml`,
  `companies/`, role ports, or the Railway/`.env` deployment surface.
  → **Downstream** — [`hcoala-in-paperclip`](https://github.com/loboroboto/hcoala-in-paperclip).

- **Unsure, or it spans both?** → file it where the *larger* half lives, label it
  `scope: needs-triage`, and call out the cross-layer part so it can be split. A
  downstream issue whose real fix is in the substrate should spawn a separate upstream
  issue rather than being implemented downstream.

## Scope labels

Every issue carries exactly one `scope:` label so its correct home is unambiguous:

| Label | Meaning |
|-------|---------|
| `scope: upstream` | Belongs in `hermes-interprets-coala` (this repo). |
| `scope: downstream` | Belongs in `hcoala-in-paperclip`. |
| `scope: needs-triage` | Layer not yet determined — **do not implement until resolved.** |

If an issue is filed in the wrong repo, maintainers relabel it `scope: upstream` /
`scope: downstream` and transfer it (`gh issue transfer <n> <dest-repo>`). The scope
labels exist in both repos so they survive the transfer.

The **New issue** chooser is wired to this boundary: each repo's templates pre-apply the
right `scope:` label, and a cross-repo link redirects work that belongs in the other repo.
