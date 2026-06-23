#!/usr/bin/env bash
# bootstrap.sh — idempotent CoALA-aligned Hermes setup.
#
# Runs on every container start (via Dockerfile ENTRYPOINT). Safe to run any
# number of times: it only writes when something is missing or stale, and
# never destroys agent-authored state on the persistent volume.
#
# Layout:
#
#   /app/hermes-config/        ← git-tracked, READ-ONLY in container
#       AGENTS.md
#       SOUL.md
#       config.yaml            ← hermes runtime config (model matrix); COPIED to
#                                the volume (no-clobber), not symlinked
#       mcp.json
#       skills/<seed-skill>/SKILL.md ...
#
#   /data/hermes/              ← Railway persistent volume, MUTABLE; this is
#                                also HERMES_HOME, so hermes writes here directly
#       state.db               ← episodic + semantic session DB (SQLite/FTS5)
#       .env, config.yaml      ← admin-server runtime config + secrets
#       MEMORY.md              ← curated semantic facts
#       USER.md                ← Honcho-style user model
#       PEERS.md               ← peer-agent semantic model (AGENTS.md §6)
#       auth.json              ← OAuth tokens (refreshed in place)
#       skills/                ← agent-authored skills land here
#       trajectories/          ← exported decision-cycle traces
#       sessions/, logs/, pairing/, cron/, hooks/, plans/,
#       image_cache/, audio_cache/, workspace/, home/
#                              ← hermes-native subdirs (created if missing)
#
#   HERMES_HOME = /data/hermes (the volume itself). hermes + the admin
#       server resolve their home from $HERMES_HOME, so state.db, .env,
#       config.yaml, sessions/, logs/, cron/, … are all written *directly*
#       onto the persistent volume — no per-file symlink to keep in sync.
#       Into that home we symlink only the read-only, git-tracked
#       architecture:
#           /data/hermes/AGENTS.md   → /app/hermes-config/AGENTS.md
#           /data/hermes/SOUL.md     → /app/hermes-config/SOUL.md
#           /data/hermes/mcp.json    → /app/hermes-config/mcp.json
#
#   ~/.hermes/   → /data/hermes   (single alias). Any code path or skill doc
#       that hardcodes ~/.hermes/... still lands on the volume.
#
# This split is the durability story:
#   - Architecture lives in code (foundation = AGENTS.md + SOUL.md + seed skills).
#   - State lives on the volume (episodic memory, learned skills, user model).
#   - A fresh deploy points HERMES_HOME at the volume and symlinks the
#     architecture in; all mutable state is already on /data, so nothing is
#     lost across redeploys.

set -euo pipefail

CONFIG_DIR="/app/hermes-config"
VOLUME_DIR="/data/hermes"
# HERMES_HOME *is* the volume — hermes writes all state here directly. Honor
# an externally-set HERMES_HOME (the Dockerfile sets it to /data/hermes) so
# this stays in lockstep with the runtime's own home resolution.
HERMES_DIR="${HERMES_HOME:-$VOLUME_DIR}"

log() { printf '[bootstrap] %s\n' "$*" >&2; }

# ----------------------------------------------------------------------------
# 1. Config dir completeness (AGENTS.md/SOUL.md/mcp.json, git-tracked;
#    missing = misbuild) is validated by seed-hermes-home.sh below — same FATAL
#    checks — so we don't duplicate them here.
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# 2. Seed the main hermes home (HERMES_HOME = the volume) + the fleet root
# ----------------------------------------------------------------------------
# All generic, idempotent home provisioning — the hermes subdir tree, .env,
# config.yaml, MEMORY/USER/PEERS, seed skills, and the read-only architecture
# symlinks — lives in the shared helper so any downstream per-agent wrapper
# seeds homes EXACTLY the same way. Railway provides the /data mount; the
# helper creates the children.
/app/seed-hermes-home.sh "$HERMES_DIR"

# Fleet root: per-agent homes (/data/hermes/agents/<agentId>) are lazily seeded
# under here on first /run by a downstream per-agent wrapper.
mkdir -p /data/hermes/agents

# ----------------------------------------------------------------------------
# 2a. Migration — durable skills moved to read-only external_dirs.
# ----------------------------------------------------------------------------
# Viajero's skills load read-only from /app/hermes-config/skills via config.yaml
# `skills.external_dirs` and are no longer seeded onto the volume. Two one-time,
# idempotent migrations for volumes seeded under the old copy scheme:
#   (a) ensure the (no-clobber-seeded) volume config.yaml exposes the external
#       dir — fresh volumes already have it from the template; older ones carry
#       `external_dirs: []`.
#   (b) remove orphaned volume copies of OUR shipped skills (exact leaf paths),
#       so the immutable image version is authoritative again. Runtime-curated
#       built-ins and agent-authored skills live at other paths, untouched.
if [[ -f "$HERMES_DIR/config.yaml" ]]; then
  python3 - "$HERMES_DIR/config.yaml" <<'PY' || log "WARN: external_dirs config patch skipped"
import sys
p = sys.argv[1]
want = "/app/hermes-config/skills"
lines = open(p, encoding="utf-8").read().splitlines()
out, in_skills, patched = [], False, False
for ln in lines:
    if ln.rstrip() == "skills:":
        in_skills = True
    elif in_skills and ln and not ln[0].isspace():
        in_skills = False
    if in_skills and ln.strip() == "external_dirs: []":
        out.append("  external_dirs:")
        out.append("  - " + want)
        patched = True
        continue
    out.append(ln)
if patched:
    open(p, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("migration: patched skills.external_dirs in volume config.yaml")
elif want not in "\n".join(lines):
    print("migration: NOTE external_dirs not in default form; verify manually", file=sys.stderr)
PY
fi
if [[ -d "$HERMES_DIR/skills" && -d "$CONFIG_DIR/skills" ]]; then
  while IFS= read -r skill_md; do
    rel_dir=$(dirname "${skill_md#"$CONFIG_DIR"/skills/}")
    if [[ -n "$rel_dir" && "$rel_dir" != "." && -e "$HERMES_DIR/skills/$rel_dir" ]]; then
      rm -rf "$HERMES_DIR/skills/$rel_dir"
      log "migration: removed orphaned volume skill copy skills/$rel_dir (now external/read-only)"
    fi
  done < <(find "$CONFIG_DIR/skills" -name SKILL.md)
fi

# ----------------------------------------------------------------------------
# 2b. Migration — prune de-listed runtime built-ins from the volume.
# ----------------------------------------------------------------------------
# The agent's /skills list reads the VOLUME ($HERMES_HOME/skills) + external_dirs.
# skills_sync seeds bundled skills onto the volume but NEVER deletes de-listed
# ones, so a volume that earlier synced the full catalog keeps them. The image
# now curates the sync SOURCE (HERMES_BUNDLED_SKILLS -> /app/curated-skills) so
# future syncs stay curated, but already-synced skills persist on the volume —
# remove them here. Discriminator: the full runtime catalog (universe of
# built-ins) minus the keep-list allowlist. A volume skill is a stale built-in
# iff it is in the catalog AND not in the allowlist; agent-authored skills are
# never in the catalog, so are always preserved. NOTE: keying off the keep-list
# (not live /opt) is deliberate — the runtime restores /opt to the full set on
# boot, so deriving "keep" from /opt would match everything and prune nothing.
# Idempotent. Set HERMES_SKIP_BUILTIN_RECONCILE=1 to opt out.
# (The external_dirs patch + orphaned-shipped-skill removal arrive with the
# hermes-config/skills port; this block only reconciles built-ins.)
CATALOG_FULL="/opt/hermes-agent/skill-catalog-full.txt"
KEEP_LIST="/app/keep-skills.txt"
if [[ "${HERMES_SKIP_BUILTIN_RECONCILE:-0}" == "1" ]]; then
  log "migration: built-in skill reconcile skipped (HERMES_SKIP_BUILTIN_RECONCILE=1)"
elif [[ -d "$HERMES_DIR/skills" && -f "$CATALOG_FULL" && -f "$KEEP_LIST" ]]; then
  python3 - "$HERMES_DIR/skills" "$CATALOG_FULL" "$KEEP_LIST" <<'PY' \
    | while IFS= read -r line; do log "$line"; done || log "WARN: built-in reconcile skipped (error)"
import os, shutil, sys

vol_skills, catalog_path, keep_path = sys.argv[1], sys.argv[2], sys.argv[3]

def skill_dirs(root):
    """rel dirs (category/skill) of every dir holding a SKILL.md under root."""
    out = set()
    if not os.path.isdir(root):
        return out
    for dp, _d, fs in os.walk(root):
        if "SKILL.md" in fs:
            rel = os.path.relpath(dp, root)
            if rel != ".":
                out.add(rel)
    return out

with open(catalog_path, encoding="utf-8") as fh:
    universe = {ln.strip() for ln in fh if ln.strip()}

keep = set()
with open(keep_path, encoding="utf-8") as fh:
    for ln in fh:
        ln = ln.strip()
        if ln and not ln.startswith("#"):
            keep.add(ln)

removed = 0
for rel in sorted(skill_dirs(vol_skills)):
    if rel in universe and rel not in keep:
        shutil.rmtree(os.path.join(vol_skills, rel), ignore_errors=True)
        print(f"migration: pruned de-listed built-in skills/{rel}")
        removed += 1

# Tidy up category dirs left empty by the prune (e.g. creative/ with no skills).
for dp, _d, fs in os.walk(vol_skills, topdown=False):
    if dp != vol_skills and not os.listdir(dp):
        os.rmdir(dp)

print(f"migration: built-in reconcile complete ({removed} de-listed built-in(s) pruned)")
PY
fi

# Clear any stale gateway PID file left over from a previous container.
# `hermes gateway` (spawned by the admin server) writes a pid file on
# start but does not always remove it on SIGTERM. Since /data is a
# persistent volume, the file survives container restarts and causes
# every subsequent boot to exit with "PID file race lost". No hermes
# process can be running this early (we're pre-exec in a fresh container),
# so removing unconditionally is safe.
rm -f "$HERMES_DIR/gateway.pid"

# Bootstrap OAuth tokens / secrets from env vars. auth.json covers providers that
# auth via OAuth device flow (xAI Grok SuperGrok, Gemini CLI, Qwen OAuth, Claude
# Code); the two Google files back the google-workspace skill's google_api.py
# (Gmail/Calendar) and are read from the home root. All are written ONCE if absent
# — subsequent refreshes update the file in place on the volume. Per-user secrets
# live under secrets/ (chmod 700). Never committed to git. Main-home only
# (per-agent fleet runs bring their own creds via the runner's per-agent env).
mkdir -p "$HERMES_DIR/secrets"
chmod 700 "$HERMES_DIR/secrets" 2>/dev/null || true

if [[ ! -f "$HERMES_DIR/auth.json" ]] && [[ -n "${HERMES_AUTH_JSON_BOOTSTRAP:-}" ]]; then
  printf '%s' "$HERMES_AUTH_JSON_BOOTSTRAP" > "$HERMES_DIR/auth.json"
  chmod 600 "$HERMES_DIR/auth.json"
  log "bootstrapped $HERMES_DIR/auth.json from HERMES_AUTH_JSON_BOOTSTRAP"
fi

if [[ ! -f "$HERMES_DIR/google_token.json" ]] && [[ -n "${HERMES_GOOGLE_TOKEN_BOOTSTRAP:-}" ]]; then
  printf '%s' "$HERMES_GOOGLE_TOKEN_BOOTSTRAP" > "$HERMES_DIR/google_token.json"
  chmod 600 "$HERMES_DIR/google_token.json"
  log "bootstrapped $HERMES_DIR/google_token.json from HERMES_GOOGLE_TOKEN_BOOTSTRAP"
fi

if [[ ! -f "$HERMES_DIR/google_client_secret.json" ]] && [[ -n "${HERMES_GOOGLE_CLIENT_SECRET_BOOTSTRAP:-}" ]]; then
  printf '%s' "$HERMES_GOOGLE_CLIENT_SECRET_BOOTSTRAP" > "$HERMES_DIR/google_client_secret.json"
  chmod 600 "$HERMES_DIR/google_client_secret.json"
  log "bootstrapped $HERMES_DIR/google_client_secret.json from HERMES_GOOGLE_CLIENT_SECRET_BOOTSTRAP"
fi

# ----------------------------------------------------------------------------
# 2d. Seed .env so the admin gate passes without the manual web /setup step.
# ----------------------------------------------------------------------------
# The HTTP front door (/opt/hermes-admin/server.py) gates the gateway on
# is_config_complete(), which reads ONLY $HERMES_HOME/.env and requires LLM_MODEL
# plus one recognized provider key — it does NOT read process env. Mirror
# recognized env vars into .env, NO-CLOBBER (only add keys not already present, so
# web-form edits and later changes win). Keys not written here are still inherited
# by the gateway via os.environ; this block exists purely to satisfy the admin
# gate + surface the values in the dashboard.
ENV_FILE="$HERMES_DIR/.env"
touch "$ENV_FILE"

# Append KEY=VALUE only if KEY is set in the environment and absent from .env.
seed_env_kv() {
  local key="$1" val
  val="${!key:-}"
  [[ -n "$val" ]] || return 0
  if ! grep -qE "^${key}=" "$ENV_FILE"; then
    printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE"
    log "seeded .env $key from environment"
  fi
}

# Provider API keys the admin gate recognizes (PROVIDER_KEYS in server.py).
# NOTE: OPENAI_API_KEY / NOUS_API_KEY are usable by the gateway but are NOT in
# this set, so they do not by themselves satisfy the gate.
PROVIDER_KEYS="OPENROUTER_API_KEY DEEPSEEK_API_KEY DASHSCOPE_API_KEY GLM_API_KEY \
KIMI_API_KEY MINIMAX_API_KEY HF_TOKEN NVIDIA_API_KEY ARCEE_API_KEY STEPFUN_API_KEY \
AI_GATEWAY_API_KEY GEMINI_API_KEY NOVITA_API_KEY FIREWORKS_API_KEY CUSTOM_PROVIDER_API_KEY"

have_provider=0
for k in $PROVIDER_KEYS; do
  if [[ -n "${!k:-}" ]]; then have_provider=1; break; fi
done

# LLM_MODEL is required by the gate. Honor an explicit override; otherwise default
# to Viajero's brain (config.yaml model.default) — but only when a provider key
# exists, so an intentionally-unconfigured deploy still falls through to /setup.
if ! grep -qE '^LLM_MODEL=' "$ENV_FILE"; then
  if [[ -n "${LLM_MODEL:-}" ]]; then
    printf 'LLM_MODEL=%s\n' "$LLM_MODEL" >> "$ENV_FILE"
    log "seeded .env LLM_MODEL from environment"
  elif (( have_provider )); then
    printf 'LLM_MODEL=%s\n' 'anthropic/claude-haiku-4.5' >> "$ENV_FILE"
    log "seeded .env LLM_MODEL default (anthropic/claude-haiku-4.5)"
  fi
fi

# Provider keys + custom-provider knobs + recognized channel vars. Telegram is
# Viajero's delivery transport (operator DM + logistics group, per AGENTS.md §7).
for k in $PROVIDER_KEYS CUSTOM_PROVIDER_BASE_URL CUSTOM_PROVIDER_NAME \
         TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_USERS \
         TELEGRAM_HOME_CHANNEL TELEGRAM_HOME_CHANNEL_THREAD_ID \
         DISCORD_BOT_TOKEN DISCORD_ALLOWED_USERS \
         SLACK_BOT_TOKEN SLACK_APP_TOKEN GATEWAY_ALLOW_ALL_USERS; do
  seed_env_kv "$k"
done

# ----------------------------------------------------------------------------
# 3. Alias ~/.hermes → the main home (main agent only)
# ----------------------------------------------------------------------------
# hermes/admin use $HERMES_HOME explicitly, but several skill docs and any code
# path that hardcodes ~/.hermes/... should still resolve onto the volume. A
# downstream per-agent wrapper can override $HOME in its own scope to give each
# agent its own ~/.hermes; this global alias belongs to the main agent only.
# Skip when HOME already *is* the home (HERMES_HOME=~/.hermes) to avoid a
# self-referential link.
HOME_HERMES="${HOME:-/root}/.hermes"
if [[ "$HOME_HERMES" != "$HERMES_DIR" ]]; then
  # Safe to clobber: pre-exec in a fresh container, the real state lives on
  # the volume this is about to point at.
  rm -rf "$HOME_HERMES"
  ln -sfn "$HERMES_DIR" "$HOME_HERMES"
fi

log "HERMES_HOME wired at $HERMES_DIR (~/.hermes → $HERMES_DIR):"
ls -la "$HERMES_DIR" | sed 's/^/[bootstrap]   /' >&2

# ----------------------------------------------------------------------------
# 5. Sanity check — required env vars
# ----------------------------------------------------------------------------
missing_env=()
[[ -z "${NOUS_API_KEY:-}" ]] && [[ -z "${OPENROUTER_API_KEY:-}" ]] && [[ -z "${OPENAI_API_KEY:-}" ]] \
  && missing_env+=("NOUS_API_KEY (or OPENROUTER_API_KEY / OPENAI_API_KEY)")

if (( ${#missing_env[@]} > 0 )); then
  log "WARN: missing recommended env vars:"
  for v in "${missing_env[@]}"; do log "  - $v"; done
  log "  (agent will run but LLM calls will fail until at least one is set)"
fi

log "bootstrap complete."

# ----------------------------------------------------------------------------
# 5b. Bootstrap overlays (downstream extension point)
# ----------------------------------------------------------------------------
# Source any *.sh files in /app/bootstrap-overlay.d/ after core setup but
# before the final exec. Downstream consumers drop their boot-time launch
# logic here without forking this script. Overlays
# are sourced — not executed — so they inherit `set -euo pipefail`, the log()
# function, and every variable resolved above. Backgrounded processes spawned
# from an overlay reparent to tini on the final `exec` exactly as inline
# launches did before.
overlay_dir="/app/bootstrap-overlay.d"
if [[ -d "$overlay_dir" ]]; then
  shopt -s nullglob
  for overlay in "$overlay_dir"/*.sh; do
    log "sourcing overlay: $overlay"
    # shellcheck disable=SC1090
    source "$overlay"
  done
  shopt -u nullglob
fi

# ----------------------------------------------------------------------------
# 6. Hand off to the actual command
# ----------------------------------------------------------------------------
# cd into the admin template dir so Jinja2's FileSystemLoader("templates")
# in server.py resolves correctly. Harmless for non-server CMDs.
cd /opt/hermes-admin 2>/dev/null || true
exec "$@"
