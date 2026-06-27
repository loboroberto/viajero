#!/usr/bin/env bash
# seed-hermes-home.sh — idempotently provision ONE CoALA-aligned hermes home.
#
# Usage: seed-hermes-home.sh <HOME_DIR>
#
# This is the single source of truth for what a hermes home must contain. It is
# called twice in two contexts:
#
#   1. bootstrap.sh — for the durable MAIN home (HERMES_HOME, the volume root
#      /data/hermes) on every container start.
#   2. Downstream per-agent wrappers — lazily, for a per-agent home under
#      /data/hermes/agents/<agentId>, the first time a host runner spawns
#      that agent.
#
# It seeds only the GENERIC, no-clobber pieces that every home needs:
#   - the hermes subdir tree
#   - .env (touched) + config.yaml (prefer git-tracked template, fall back to
#     the runtime's bundled example)
#   - MEMORY.md / USER.md / PEERS.md (if absent)
#   - references/ travel knowledge base (copied no-clobber; HERMES_FORCE_RESEED=1
#     refreshes it from /app)
#   - bundled seed skills (copied, so agent edits survive; HERMES_FORCE_RESEED=1
#     overwrites them from /app)
#   - symlinks to the read-only, git-tracked architecture (AGENTS.md, SOUL.md,
#     mcp.json). config.yaml is COPIED (no-clobber), not symlinked, because the
#     hermes runtime rewrites it in place (version migrations, onboarding flags).
#
# It deliberately does NOT touch the global ~/.hermes alias, gateway.pid, or
# auth.json — those are main-home concerns owned by bootstrap.sh (the fleet
# wrapper handles ~/.hermes per-agent via $HOME instead).
#
# Idempotent: safe to run any number of times. It only writes when something is
# missing or stale and never destroys agent-authored state.

set -euo pipefail

CONFIG_DIR="/app/hermes-config"

HOME_DIR="${1:-}"
if [[ -z "$HOME_DIR" ]]; then
  printf '[seed-home] FATAL: no target home dir given (usage: %s <HOME_DIR>)\n' "$0" >&2
  exit 1
fi

log() { printf '[seed-home] %s\n' "$*" >&2; }

# Config dir is git-tracked; missing = misbuild.
if [[ ! -d "$CONFIG_DIR" ]]; then
  log "FATAL: $CONFIG_DIR not found — Dockerfile didn't copy hermes-config in."
  exit 1
fi
for f in AGENTS.md SOUL.md mcp.json; do
  if [[ ! -f "$CONFIG_DIR/$f" ]]; then
    log "FATAL: $CONFIG_DIR/$f missing — config is incomplete."
    exit 1
  fi
done

# ----------------------------------------------------------------------------
# 1. Ensure the hermes subdir tree exists.
# ----------------------------------------------------------------------------
# The full set hermes expects to find under a home. Missing dirs can cause
# opaque "no such file" errors deep in cron / session / log code paths even
# when the user-facing feature isn't being exercised directly.
mkdir -p "$HOME_DIR" \
         "$HOME_DIR/skills" \
         "$HOME_DIR/trajectories" \
         "$HOME_DIR/memory" \
         "$HOME_DIR/references/employers" \
         "$HOME_DIR/cron" \
         "$HOME_DIR/sessions" \
         "$HOME_DIR/logs" \
         "$HOME_DIR/pairing" \
         "$HOME_DIR/hooks" \
         "$HOME_DIR/image_cache" \
         "$HOME_DIR/audio_cache" \
         "$HOME_DIR/workspace" \
         "$HOME_DIR/plans" \
         "$HOME_DIR/onboarding" \
         "$HOME_DIR/home"

# Seed runtime state files hermes/admin read/write. The admin server expects
# both to exist and barfs on missing files.
#   .env          — operator-set secrets and runtime toggles.
#   config.yaml   — hermes runtime config (model matrix, toolsets, etc.). Prefer
#                   our git-tracked template (carries the per-responsibility
#                   model matrix); fall back to the runtime's bundled example so
#                   the agent still boots if the template is ever absent.
#                   No-clobber by default so runtime/dashboard edits survive
#                   redeploys; HERMES_FORCE_RESEED=1 overwrites from the git
#                   template (merge any wanted runtime drift back into git FIRST).
touch "$HOME_DIR/.env"
if [[ ! -f "$HOME_DIR/config.yaml" ]]; then
  if [[ -f "$CONFIG_DIR/config.yaml" ]]; then
    cp "$CONFIG_DIR/config.yaml" "$HOME_DIR/config.yaml"
    log "seeded $HOME_DIR/config.yaml from git-tracked template"
  elif [[ -f /opt/hermes-agent/cli-config.yaml.example ]]; then
    cp /opt/hermes-agent/cli-config.yaml.example "$HOME_DIR/config.yaml"
    log "seeded $HOME_DIR/config.yaml from bundled example"
  fi
elif [[ "${HERMES_FORCE_RESEED:-0}" == "1" ]] && [[ -f "$CONFIG_DIR/config.yaml" ]]; then
  cp "$CONFIG_DIR/config.yaml" "$HOME_DIR/config.yaml"
  log "re-seeded $HOME_DIR/config.yaml from git-tracked template (HERMES_FORCE_RESEED=1)"
fi

# integrations.yaml — non-secret integration knobs (reconciliation cadence, alert
# lead, calendar colors, label names). No-clobber; seeded once if the git
# template is present (lands with #9). Guard makes this a no-op until then.
if [[ ! -f "$HOME_DIR/integrations.yaml" ]] && [[ -f "$CONFIG_DIR/integrations.yaml" ]]; then
  cp "$CONFIG_DIR/integrations.yaml" "$HOME_DIR/integrations.yaml"
  log "seeded $HOME_DIR/integrations.yaml"
fi

# cron/jobs.json — reconciliation / flight-alert / divergence-audit job templates.
# No-clobber; seeded once if the git template is present (lands with #9).
if [[ ! -f "$HOME_DIR/cron/jobs.json" ]] && [[ -f "$CONFIG_DIR/cron/jobs.json" ]]; then
  cp "$CONFIG_DIR/cron/jobs.json" "$HOME_DIR/cron/jobs.json"
  log "seeded $HOME_DIR/cron/jobs.json"
fi

# references/ — user-agnostic travel domain knowledge (StandardBooking schema,
# provider patterns, calendar conventions, gmail-ops contract, employer definitions).
# Copied onto the volume so the agent reads them home-relative (references/<doc>.md)
# AND can author/augment them (e.g. onboarding writes references/employers/<principal>.md;
# a read-only symlink would block that write). No-clobber so agent additions survive
# redeploys; HERMES_FORCE_RESEED=1 refreshes from git (merge wanted runtime drift back
# into git FIRST — a forced reseed is a full overwrite; see tools/divergence_scan.py).
if [[ -d "$CONFIG_DIR/references" ]]; then
  if [[ "${HERMES_FORCE_RESEED:-0}" == "1" ]]; then
    cp -r "$CONFIG_DIR/references/." "$HOME_DIR/references/"
    log "re-seeded references/ (HERMES_FORCE_RESEED=1)"
  else
    cp -rn "$CONFIG_DIR/references/." "$HOME_DIR/references/" 2>/dev/null || true
    log "seeded references/ (no-clobber)"
  fi
fi

# ----------------------------------------------------------------------------
# 2. Seed MEMORY.md / USER.md / PEERS.md if absent (agent appends over time).
# ----------------------------------------------------------------------------
if [[ ! -f "$HOME_DIR/MEMORY.md" ]]; then
  cat > "$HOME_DIR/MEMORY.md" <<'EOF'
# MEMORY.md — Curated Semantic Memory

This file is the agent's hand-curated semantic memory (CoALA §4.1, §4.5).
Stable facts about the user, infrastructure, and codebase, written as
declarative sentences with sources. Updated by the `coala-reflection` skill
and by direct user instruction.

## Format
```
## <topic>
- Claim. (Source: episode <id>, <date>.)
```

## User
_(empty — populated as the agent learns)_

## Infrastructure
_(empty — populated as the agent learns)_

## Codebase
_(empty — populated as the agent learns)_
EOF
  log "seeded $HOME_DIR/MEMORY.md"
fi

if [[ ! -f "$HOME_DIR/USER.md" ]]; then
  cat > "$HOME_DIR/USER.md" <<'EOF'
# USER.md — User Model

Dialectic user model (Honcho-style if enabled, otherwise hand-curated).
What the agent has inferred about the user's preferences, working style,
and goals. Distinct from MEMORY.md: claims here are *about the user*
specifically.

_(empty — populated as the agent learns)_
EOF
  log "seeded $HOME_DIR/USER.md"
fi

# Onboarding gate state. The onboarding gate (AGENTS.md §1.1; the `onboarding`
# skill, added in a later issue) reads/writes this flag; it lives in THIS home
# (never USER.md, a shared context file) so it gates per-home. No-clobber: an
# already-onboarded home keeps its flag across reseeds. agentId is the home's
# basename for /data/hermes/agents/<id>; empty for the main home. Honor
# HERMES_ONBOARDING_STATE_PATH if set (downstream may relocate the gate file);
# default keeps the per-home layout. NOTE: the JSON shape below (humanOnboarded)
# is the legacy fleet shape; #10/#3 reconcile it to the onboarding skill's
# `onboarded` flag when that skill lands.
state_file="${HERMES_ONBOARDING_STATE_PATH:-$HOME_DIR/onboarding/state.json}"
if [[ ! -f "$state_file" ]]; then
  case "$HOME_DIR" in
    /data/hermes/agents/*) agent_id="${HOME_DIR##*/}" ;;
    *)                     agent_id="" ;;
  esac
  mkdir -p "$(dirname "$state_file")"
  cat > "$state_file" <<EOF
{
  "humanOnboarded": false,
  "gateActive": false,
  "agentId": "$agent_id",
  "firstContactAt": null,
  "onboardedAt": null,
  "onboardedBy": null,
  "channel": null
}
EOF
  log "seeded $state_file (humanOnboarded=false)"
fi

if [[ ! -f "$HOME_DIR/PEERS.md" ]]; then
  cat > "$HOME_DIR/PEERS.md" <<'EOF'
# PEERS.md — Peer Agent Model

Semantic memory (CoALA §4.1, §4.5) for other agents the system shares
work with. Parallel to USER.md but for non-human collaborators. See
AGENTS.md §6.

Claims here are about specific peers: their identity, declared
capabilities, observed behavior, trust level, and which channels they
monitor. Updated by direct user instruction, by the `coala-reflection`
skill, and by the `group-agent-coordination` skill when a cycle
produces a durable fact about a peer.

Registered peers in `hermes.toml [[peers.peer]]` are the *declaration*;
this file is the *experience-grounded* model. They drift apart over time
— that's expected. Reconcile during reflection.

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
EOF
  log "seeded $HOME_DIR/PEERS.md"
fi

# ----------------------------------------------------------------------------
# 3. Skills load READ-ONLY from the image (NOT seeded onto the volume).
# ----------------------------------------------------------------------------
# The git-tracked skills in /app/hermes-config/skills/ are exposed to the agent
# via config.yaml `skills.external_dirs: [/app/hermes-config/skills]`, NOT copied
# onto the writable volume. This makes them immutable-but-augmentable: refreshed
# from the image every deploy, the agent can author NEW skills (they land in
# $HOME_DIR/skills, the runtime's local skills dir) but cannot durably edit the
# shipped ones. The volume's skills/ therefore holds only runtime-curated
# built-ins (skills_sync) + agent-authored augmentation. bootstrap.sh handles the
# one-time migration for volumes previously seeded with copies of our skills.
log "skills/ load read-only from external_dirs (not seeded onto the volume)"

# ----------------------------------------------------------------------------
# 4. Symlink the read-only, git-tracked architecture + tools into the home.
# ----------------------------------------------------------------------------
# All mutable state is written directly into the home; only the architecture and
# tool implementations are linked to the (always-current) git-tracked sources.
ln -sfn "$CONFIG_DIR/AGENTS.md"   "$HOME_DIR/AGENTS.md"
ln -sfn "$CONFIG_DIR/SOUL.md"     "$HOME_DIR/SOUL.md"
ln -sfn "$CONFIG_DIR/mcp.json"    "$HOME_DIR/mcp.json"
ln -sfn "$CONFIG_DIR/tools"       "$HOME_DIR/tools"

# ----------------------------------------------------------------------------
# 5. Record the seed baseline manifest (sha256 per seeded file + commit).
# ----------------------------------------------------------------------------
# Snapshot of the GIT-tracked seed (CONFIG_DIR), keyed by the HOME-relative path
# each file maps to — memory/ templates map to the ROOT MEMORY.md/USER.md/PEERS.md
# (viajero keeps memory at the home root, not a memories/ subdir). tools/
# divergence_scan.py uses /app/hermes-config directly as its baseline; this
# manifest is the fallback for when that dir is absent (diffing a pulled-down
# volume locally) + an explicit record of the commit the volume was last seeded
# from. Always rewritten — the seed is the source of truth.
python3 - "$CONFIG_DIR" "$HOME_DIR" "${RAILWAY_GIT_COMMIT_SHA:-unknown}" <<'PY' || log "WARN: could not write .seed-manifest.json"
import hashlib, json, os, sys
config_dir, home_dir, commit = sys.argv[1], sys.argv[2], sys.argv[3]
files = {}
def sha(p):
    with open(p, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()
# Recursive trees, keyed by home-relative prefix.
for sub, prefix in (("skills", "skills"), ("references", "references")):
    root = os.path.join(config_dir, sub)
    if not os.path.isdir(root):
        continue
    for dp, _d, fs in os.walk(root):
        for n in fs:
            full = os.path.join(dp, n)
            files[f"{prefix}/{os.path.relpath(full, root)}"] = sha(full)
# Memory templates: git memory/<X> -> ROOT <X> on the volume.
for name in ("MEMORY.md", "USER.md", "PEERS.md"):
    full = os.path.join(config_dir, "memory", name)
    if os.path.isfile(full):
        files[name] = sha(full)
# Single files at the root.
for name in ("config.yaml", "integrations.yaml", "cron/jobs.json"):
    full = os.path.join(config_dir, name)
    if os.path.isfile(full):
        files[name] = sha(full)
out = {"commit": commit, "files": files}
with open(os.path.join(home_dir, ".seed-manifest.json"), "w", encoding="utf-8") as fh:
    json.dump(out, fh, indent=2)
PY
log "wrote $HOME_DIR/.seed-manifest.json"
