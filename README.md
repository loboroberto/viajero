# Viajero — Autonomous Travel-Operations Agent

Viajero is an autonomous **travel-operations agent** built on a Hermes Agent
([NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent))
deployment whose foundational configuration is explicitly oriented toward the
**Cognitive Architectures for Language Agents (CoALA)** framework — Sumers, Yao,
Narasimhan & Griffiths, [arXiv:2309.02427v3](https://arxiv.org/html/2309.02427v3).

It reconciles a principal traveler's email and calendar autonomously: scan
booking confirmations → parse into a standard form → reconcile against the
calendar → alert the travel party on imminent arrivals → stay silent otherwise.
It is **user-agnostic by construction** — a fresh deploy carries no traveler's
data; an onboarding gate turns the generic deployment into one principal's travel
agent (`hermes-config/AGENTS.md` §1.1). All principal-specific data lives on the
persistent volume, never in git.

Hermes provides the substrate (skills, memory, tools, MCP, messaging gateways);
CoALA provides the schema imposed on that substrate. The pairing is durable,
git-tracked, and reconstitutes a fresh Railway deploy into the same architecture
on every boot.

---

## Repository Layout

```
.
├── README.md                       ← you are here
├── railway.toml                    ← Railway build/deploy config
├── .env.example                    ← committed template; copy to .env for local dev
├── .dockerignore
├── .gitignore
│
├── docker/
│   ├── Dockerfile                  ← uv + tini + pinned Hermes + pre-built ui-tui
│   └── keep-skills.txt             ← curated allowlist of built-in Hermes skills to retain
│
├── scripts/
│   ├── bootstrap.sh                ← idempotent setup on every container boot
│   └── seed-hermes-home.sh         ← provisions a hermes home (architecture + state)
│
└── hermes-config/                  ← THE ARCHITECTURE (git-tracked, durable)
    ├── AGENTS.md                   ← CoALA system prompt (memory, actions, decision cycle; §7 travel posture)
    ├── SOUL.md                     ← persona / voice (travel-ops)
    ├── config.yaml                 ← provider, per-responsibility model matrix, toolsets, paths
    ├── mcp.json                    ← MCP grounding-action surfaces (github live; others commented)
    └── skills/                     ← seed procedural memory
        ├── coala-decision-cycle/      ← META — the loop, made explicit
        ├── coala-skill-induction/     ← META — how to write a skill (procedural learning)
        ├── coala-reflection/          ← META — episodic → semantic promotion
        ├── group-agent-coordination/  ← META — peer claims, hand-offs (dormant; single-principal)
        ├── channel-aware-messaging/   ← META — pick the right channel; respect etiquette
        └── viajero/                   ← DOMAIN — travel-ops skills (parsing, reconciliation, alerts)
```

> The seed skill set is mid-specialization for travel ops: the substrate's
> generic DevOps skills and the fleet onboarding handshake are removed (issue
> #5), and the principal's travel skills — provider parsers, the
> `StandardBooking` interchange, calendar reconciliation, flight alerts — land
> under `skills/viajero/` (issue #6). Built-in Hermes skills are curated by
> `docker/keep-skills.txt` (Gmail/Calendar, document/receipt OCR, web search).

---

## CoALA → Hermes Mapping

This is the foundational mapping. Each CoALA primitive (left) is realized by
a specific Hermes mechanism (right).

| CoALA primitive (§ in paper)               | Hermes substrate                              | Where it lives                                |
|--------------------------------------------|-----------------------------------------------|-----------------------------------------------|
| **Working memory** (§4.1)                  | Conversation context + context files          | runtime; `AGENTS.md` + `SOUL.md` always loaded |
| **Episodic memory** (§4.1)                 | FTS5-indexed session history (SQLite)         | `/data/hermes/state.db`                        |
| **Semantic memory** (§4.1)                 | Curated facts file + Honcho user model        | `/data/hermes/MEMORY.md`, `USER.md`            |
| **Procedural memory — implicit** (§4.1)    | LLM weights                                   | provider (Nous Portal / OpenRouter / etc.)     |
| **Procedural memory — explicit** (§4.1)    | Skills + AGENTS.md + decision scaffolds       | `/app/hermes-config/skills/` + `/data/hermes/skills/` |
| **Grounding actions** (§4.2)               | Built-in tools (shell, fs, web, etc.) + MCP servers | `config.yaml` toolsets + `mcp.json`      |
| **Retrieval actions** (§4.3)               | `memory_search`, skill index, context loading | runtime                                        |
| **Reasoning actions** (§4.4)               | LLM calls scaffolded by AGENTS.md             | runtime                                        |
| **Learning actions** (§4.5)                | Memory writes + `skill_manage` for skill author/patch | runtime, persists to `/data`            |
| **Decision cycle** (§4.6 propose/eval/select) | Encoded in `AGENTS.md` §4 + `coala-decision-cycle` skill | both prompt-level and skill-level     |
| **Multi-agent grounding** (§4.2 dialogue, other agents) | Peer semantic model + MCP transports (**dormant** — single-principal) | `/data/hermes/PEERS.md` + `mcp.json` |
| **Group decision cycle** (§4.6 in groups)  | Local cycle with group-coherence criterion + coordination primitives | `AGENTS.md` §6 + `group-agent-coordination` skill |

The live channel model — operator DM vs. logistics group — is the travel
posture in `AGENTS.md` §7; channels are configured via `config.yaml` (messaging
gateways) and the principal's memory-key contract, not a static registry.

The agent itself can produce a CoALA self-audit when asked — it knows its
own schema.

---

## Durability Story

The foundation is **declarative and re-applyable**. A fresh Railway deploy:

1. Builds the image from `docker/Dockerfile` — installs Hermes, the curated
   built-in skill set, and copies `hermes-config/` into `/app/`.
2. Mounts the persistent volume at `/data`.
3. Runs `scripts/bootstrap.sh` (the ENTRYPOINT, wrapped in `tini` as PID 1
   so MCP stdio servers and other subprocess fanout get reaped cleanly and
   `SIGTERM` propagates through the whole process group), which:
   - Verifies `/app/hermes-config/` is complete (via `seed-hermes-home.sh`).
   - Creates the full set of `/data/hermes/` subdirectories hermes expects
     (cron, sessions, logs, pairing, hooks, image_cache, audio_cache,
     workspace, plans, onboarding, home, plus our memory/skills/trajectories).
   - Clears any stale `gateway.pid` lockfile from a prior container.
   - Bootstraps OAuth tokens to `/data/hermes/auth.json` if
     `HERMES_AUTH_JSON_BOOTSTRAP` is set and no file exists yet.
   - Seeds `MEMORY.md`, `USER.md`, `PEERS.md`, and `onboarding/state.json` if
     missing (idempotent — won't clobber).
   - Seeds `config.yaml` from the git-tracked template if missing (no-clobber;
     `HERMES_FORCE_RESEED=1` to overwrite), and copies seed skills into
     `/data/hermes/skills/` so agent patches stick.
   - Reconciles built-in skills against `keep-skills.txt` (prunes de-listed
     built-ins already synced onto the volume; agent-authored skills are kept).
   - Points `HERMES_HOME` at the volume (`/data/hermes`) so hermes and the
     admin server write **all** state (`state.db`, `.env`, `config.yaml`,
     `sessions/`, `logs/`, …) directly onto the volume — **state persists
     across deploys** with no per-file symlink to keep in sync.
   - Symlinks `$HERMES_HOME/AGENTS.md`, `SOUL.md`, `mcp.json` to the git-tracked
     `/app/` versions — **architecture is always fresh from the repo** —
     copies `config.yaml` (the runtime rewrites it in place), and aliases
     `~/.hermes` → the volume so any hardcoded `~/.hermes/...` path resolves there.
4. Execs the CMD (`hermes serve`).

The image bakes a **pinned hermes-agent version** (via the `HERMES_REF`
build arg, default `v2026.5.16`) instead of `pip install` against the
latest, so rebuilds are reproducible. Bump it deliberately when you want
a new upstream.

**What's on the volume (mutable, persistent):**
`state.db` (episodic/session DB), `.env`, `config.yaml`, `MEMORY.md`,
`USER.md`, `PEERS.md`, agent-authored skills, trajectories, sessions, logs.

**What's in git (immutable, declarative):**
the system prompt (`AGENTS.md`), `SOUL.md`, the `config.yaml` template,
`mcp.json`, the seed skill set.

You can wipe and redeploy Railway, lose nothing about who the agent is, and
keep everything about what it's learned.

---

## Group Operation (dormant by default)

Viajero serves **one principal** and has no peer agents by default, so the
multi-agent layer (`AGENTS.md` §6) is **dormant**: all dialogue is
`user-dialogue` with the operator plus outbound `delivery` to the logistics
group via the messaging gateway. The CoALA peer/channel architecture is still
present and activates if a peer is ever registered in `/data/hermes/PEERS.md`,
but nothing is wired out of the box.

The **live** channel model is the travel posture in `AGENTS.md` §7:

| Channel        | Kind / visibility            | What flows                                              | Configured by                          |
|----------------|------------------------------|---------------------------------------------------------|-----------------------------------------|
| **Operator DM** | `human` / `private` / `sync` | infra failures, decision gates, anomalies (terse, technical) | `config.yaml` gateway + `dm_chat_id`    |
| **Logistics group** | `group` / `public` / `async` | flight arrivals, routes, status, raw links (arrival-focused, locale-aware) | `config.yaml` gateway + `travel_notify_chat_id` |

Messaging transport (e.g. Telegram) is an MCP/gateway concern in `config.yaml`;
the two channel IDs are principal-specific memory keys collected at onboarding.
The GitHub MCP remains available as a grounding transport (set `GITHUB_TOKEN`)
but wires no peer channels by default.

---

## Quick Start

### 1. Push to your Railway project

```bash
git clone <this-repo>
cd <this-repo>
railway link <your-project-id>
railway up
```

For **local dev** (`docker run` against a named volume) instead of Railway:
copy `.env.example` to `.env`, fill in real values, then:

```bash
docker build -t viajero -f docker/Dockerfile .
docker run --rm -it --env-file .env -v hermes-data:/data viajero
```

### 2. Configure the volume in the Railway dashboard

- **Mount path:** `/data` (must match `HERMES_HOME=/data/hermes`)
- **Size:** ≥ 1GB (state.db + skills + trajectories grow over time)

### 3. Set required env vars

In the Railway dashboard:

| Variable                  | Required? | Purpose                                    |
|---------------------------|-----------|--------------------------------------------|
| `ADMIN_USERNAME`          | Recommended | Username for the web admin login. Defaults to `admin` if unset. |
| `ADMIN_PASSWORD`          | Recommended | Password for the web admin login. If unset, a random 16-char token is generated on boot and printed to deploy logs. Cookie secret regenerates on every boot, so redeploys invalidate sessions. |
| `NOUS_API_KEY`            | Yes¹      | LLM provider (Nous Portal)                 |
| `OPENROUTER_API_KEY`      | Yes¹      | LLM provider (the model matrix targets OpenRouter) |
| `OPENAI_API_KEY`          | Yes¹      | Alternative provider                       |
| `TELEGRAM_BOT_TOKEN`      | Recommended | Telegram gateway — the delivery transport for the operator DM + logistics group |
| `GITHUB_TOKEN`            | Optional² | GitHub MCP grounding transport — live by default |
| `RAILWAY_TOKEN`           | Optional  | Railway MCP / programmatic Railway access  |
| `DISCORD_BOT_TOKEN`       | Optional  | Discord gateway                            |
| `SLACK_BOT_TOKEN`         | Optional  | Slack gateway                              |
| `HERMES_AUTH_JSON_BOOTSTRAP` | Optional | Contents of a locally-generated `~/.hermes/auth.json`. Written to `/data/hermes/auth.json` on first boot, then refreshed in place. Use for OAuth-based providers — avoids the interactive device-flow on first run. |
| `HERMES_FORCE_RESEED`     | Optional  | Set to `1` to overwrite agent-patched seed skills / `config.yaml` from the git template on next boot |

¹ At least one provider key is required; pick the one matching `model.provider`
in `config.yaml` (the matrix defaults to OpenRouter).

² Without `GITHUB_TOKEN`, the GitHub MCP errors at call-time but doesn't
crash the agent — the transport is simply unreachable and the agent will say so
on attempted use.

> Gmail/Calendar access (the reconciliation engine) is provided by the built-in
> `google-workspace` skill and authenticates via OAuth — those tokens are
> bootstrapped at migration/onboarding, not set here. See `AGENTS.md` §1.1 and
> the onboarding flow.

### 4. Activate any MCP servers you want

Edit `hermes-config/mcp.json`. The `github` entry is **live by default**
(set `GITHUB_TOKEN` to use it). Other entries are commented out with `_disabled`
markers — rename `_foo_example` → `foo` (and drop `_disabled` / `_note`) to
activate. Messaging delivery (Telegram for the operator DM + logistics group) is
configured via `config.yaml` and the principal's memory keys, not here;
group-agent peers are dormant (`AGENTS.md` §6). Commit, redeploy.

### 5. Open the web admin

Open the Railway-assigned URL in a browser. Log in with `ADMIN_USERNAME`
(default `admin`) and `ADMIN_PASSWORD`. If you didn't set `ADMIN_PASSWORD`,
grep the deploy logs for `Admin credentials —` to find the auto-generated
one.

The dashboard surfaces:

- **Web UI / chat** — talk to the agent directly from the browser (proxied
  through to `hermes dashboard`).
- **Live status** — gateway state, uptime, model in use.
- **Streaming logs** — gateway + dashboard subprocess output.
- **User pairing** — approve/deny/revoke channel users (Telegram, Discord, Slack).
- **Runtime config** — set provider keys and channel tokens.

The HTTP front door is a pinned clone of
[`praveen-ks-2001/hermes-agent-template`](https://github.com/praveen-ks-2001/hermes-agent-template)
(see `HERMES_ADMIN_REF` in `docker/Dockerfile`).

### 6. Talk to it through messaging gateways

If you enabled a messaging gateway (Telegram, Discord, Slack), message the
agent there directly. For interactive terminal debugging:

```bash
railway run -- hermes --tui
```

---

## Modifying the Architecture

Because the architecture is git-tracked, all changes are PR-reviewable.

| To change…                                  | Edit                                          |
|---------------------------------------------|-----------------------------------------------|
| How the agent thinks (memory schema, action types, decision cycle) | `hermes-config/AGENTS.md` |
| The travel posture (calendar doctrine, channel boundaries, alert format) | `hermes-config/AGENTS.md` §7 |
| How the agent talks (voice, tone, persona)  | `hermes-config/SOUL.md`                        |
| Which model per responsibility, which provider | `hermes-config/config.yaml` `model` / `auxiliary` |
| Which tools are enabled                     | `hermes-config/config.yaml` `toolsets`         |
| External grounding surfaces (APIs, services) | `hermes-config/mcp.json`                      |
| Group-agent peers (dormant)                 | `/data/hermes/PEERS.md` (see [Group Operation](#group-operation-dormant-by-default)) |
| Seed procedural knowledge                   | `hermes-config/skills/<name>/SKILL.md` (add/edit) |
| Where state persists                        | `config.yaml` `data_dir` + `bootstrap.sh` / `seed-hermes-home.sh` |

Commit, push, redeploy. Bootstrap is idempotent — re-running it never
destroys volume state.

**Dashboard vs git-tracked architecture.** The web admin can edit *runtime
state on the volume* — operator-set secrets in `/data/hermes/.env`,
gateway lifecycle, pairing approvals. It does **not** edit
`hermes-config/*`. Those files are git-tracked, the source of truth for
architecture (provider/model matrix, toolsets, seed skills, travel posture,
safety policies). Dashboard config changes do not round-trip into git — if you
want a change to survive a volume wipe, make it in `hermes-config/` and redeploy.

---

## Verifying CoALA Alignment

Ask the agent (in a session):

> Walk me through your architecture. Name each memory module, where it
> lives, and the four action types. Then describe your decision cycle.

A well-aligned agent will reproduce §2 and §4 of `AGENTS.md` in its own
words, with CoALA section references. If it can't, the system prompt isn't
loading — check that `~/.hermes/AGENTS.md` symlinks correctly to
`/app/hermes-config/AGENTS.md`.

And for travel-posture alignment:

> A booking confirmation just landed in the configured inbox, and a flight
> arriving at the home airport is 30 hours out. Walk me through your decision
> cycle — which memory you read, the reconcile/dedup steps, the
> silence-vs-alert decision, which channel each output goes to, and which
> `AGENTS.md` section governs the call.

A well-aligned agent will treat the calendar as source of truth (§7), reconcile
and dedup by RFC822 `Message-ID`, route the arrival alert to the **logistics
group only** as a raw-URL checklist (no markdown), keep the operator DM silent,
emit `[SILENT]` when nothing is actionable, and cite `AGENTS.md` §7.

---

## License

Apply whatever license fits your project. Hermes Agent itself is MIT.
The CoALA paper is CC-BY-4.0.
