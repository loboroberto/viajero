# Dockerfile — CoALA-aligned Hermes Agent on Railway
#
# Single-stage layout (uv-based):
#   - Architecture lives in /app/hermes-config (read-only from agent's POV).
#   - State lives in /data (Railway-mounted persistent volume).
#   - HERMES_HOME points at the volume (/data/hermes), so hermes + the admin
#     server write all state (state.db, .env, config.yaml, sessions, …)
#     directly onto the persistent volume. Bootstrap symlinks the read-only
#     architecture into that home and aliases ~/.hermes → the volume.
#
# Operational lessons borrowed from praveen-ks-2001/hermes-agent-template:
#   - tini as PID 1 to reap zombies (long-uptime containers with MCP stdio
#     servers, browser daemons, etc. otherwise pile up zombies and eventually
#     hit the kernel PID-table limit → "fork: cannot allocate memory").
#   - Pinned HERMES_REF for reproducibility instead of unpinned pip install.
#   - Pre-build the hermes ui-tui bundle so `hermes --tui` (referenced in our
#     README's interactive-debug section) doesn't freeze 30-60s on first
#     connection doing npm install.
#   - uv-based image for faster Python installs.

FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    HOME=/root \
    HERMES_CONFIG_DIR=/app/hermes-config \
    HERMES_HOME=/data/hermes

# Which hermes-agent revision to install. Accepts any git ref the upstream
# repo publishes — a release tag (recommended for reproducibility) or a
# branch name (`main`) for bleeding edge.
#
# To bump: check https://github.com/NousResearch/hermes-agent/releases for
# the newest tag (format `vYYYY.M.D`) and update the default below. Use
# `main` only if you accept that every rebuild can pull arbitrary new
# upstream commits.
ARG HERMES_REF=v2026.5.16

# Which praveen-ks-2001/hermes-agent-template revision to install. The
# template provides the Starlette admin server (cookie auth gated by
# ADMIN_USERNAME / ADMIN_PASSWORD) that wraps `hermes gateway` + `hermes
# dashboard` and is our HTTP front door.
#
# Pinned to a SHA, not a branch — the upstream has no release tags and we
# want reproducible rebuilds. To bump, check
# https://github.com/praveen-ks-2001/hermes-agent-template/commits/main
# and replace the SHA below.
#
# If we ever need to modify the dashboard (strip "Reset Config", reframe the
# config editor for our git-tracked architecture, etc.) fork the upstream
# and repoint the URL in the RUN below to the fork. Until then, we consume
# unmodified.
ARG HERMES_ADMIN_REF=935ead16bcf9905b06637058dd68fe3137775e8c

# tini = tiny init that runs as PID 1. Without it, hermes's grandchild
# processes (MCP stdio servers, git, bun, browser daemons spawned by tools)
# reparent to PID 1 when their parents exit and pile up as zombies. After
# weeks of uptime that exhausts the kernel's PID table → "fork: cannot
# allocate memory" and the container dies. tini reaps zombies in the
# background and forwards SIGTERM/SIGINT to our entrypoint so Railway's
# stop signal still triggers our graceful shutdown.
#
# The apt + tooling install is split into three layers below — same final
# image, but BuildKit can checkpoint between them. Earlier attempts that
# chained apt-base + nodesource + nodejs + railway-CLI into one compound
# RUN were silently killed by Railway's BuildKit worker mid-step with no
# error in the log (deploys 511106c3 + 5d1bcff2). Splitting bounds peak
# per-layer memory and turns any future failure into a diagnostic signal
# (we'll see which specific layer failed instead of "the big RUN died").

# Layer 1: base apt packages. Kept small and self-contained so BuildKit
# can checkpoint cleanly before the heavier node + railway steps.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        tini \
        git \
        curl \
        ca-certificates \
        sqlite3 \
        jq \
        openssh-client && \
    rm -rf /var/lib/apt/lists/*

# Layer 2: Node.js 22 via nodesource. The setup script pulls its own
# gnupg / apt-transport-https deps and adds the nodesource repo; running
# it in its own layer (instead of chained with the base apt install
# above) isolates its memory footprint and makes failures here visible.
# Required only at build time for the hermes ui-tui and web bundles.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Layer 3: Railway CLI. Used at runtime by the deploy-railway skill and
# by the agent for Railway MCP / CLI grounding (RAILWAY_TOKEN). Tiny
# install — its own layer purely for diagnostic clarity if it ever breaks.
RUN curl -fsSL https://railway.app/install.sh | sh -s -- --yes --bin-dir /usr/local/bin

# Install hermes-agent (provides the `hermes` CLI) at pinned ref. The [all]
# extras in current hermes pull cron, cli, dev, pty, mcp, homeassistant,
# sms, acp, google, web, youtube. Heavy backends (messaging gateways, TTS,
# Honcho, Bedrock/Anthropic, edge-tts, hindsight) are pre-installed via
# explicit extras so first-message latency is instant and the agent can
# opt in to any of them at config time without a rebuild.
#
# When bumping HERMES_REF, re-check hermes-agent's pyproject.toml [all]
# and the extras list against the new release.
RUN git clone --depth 1 --branch ${HERMES_REF} \
        https://github.com/NousResearch/hermes-agent.git /opt/hermes-agent && \
    cd /opt/hermes-agent && \
    uv pip install --system --no-cache -e ".[all,messaging,tts-premium,honcho,bedrock,anthropic,edge-tts,hindsight]" && \
    cd /opt/hermes-agent/web && \
    npm install --silent --no-fund --no-audit --progress=false && \
    npm run build && \
    cd /opt/hermes-agent/ui-tui && \
    npm install --silent --no-fund --no-audit --progress=false && \
    npm run build && \
    rm -rf /opt/hermes-agent/.git /root/.npm

# Curate the runtime's built-in skill catalog.
#
# The agent's /skills list is built from the VOLUME ($HERMES_HOME/skills) plus the
# read-only external_dirs — NOT from /opt. The runtime ships ~168 skills under
# /opt/hermes-agent/{skills,optional-skills} and skills_sync seeds the *bundled*
# set onto the volume on boot, where it accumulates: sync never deletes, so the
# volume balloons with mostly-irrelevant capabilities (creative/, gaming/,
# mlops/, …). Pruning /opt at build time does NOT help — the runtime restores
# /opt to the full set on boot, and /skills doesn't read /opt anyway.
#
# So we curate the SYNC SOURCE instead: build a dir with just the keep-list skills
# and point skills_sync at it via HERMES_BUNDLED_SKILLS (honored by
# tools/skills_sync._get_bundled_dir). Only these skills ever seed onto the
# volume. /opt is left intact so optional-skills remain installable on demand.
# bootstrap.sh then removes already-synced de-listed skills from existing volumes.
# Viajero's OWN skills live in hermes-config/skills and load read-only via
# skills.external_dirs — never seeded onto the volume (immutable but augmentable).
COPY docker/keep-skills.txt /app/keep-skills.txt
RUN set -eu; \
    : "Snapshot the FULL runtime catalog (category/skill, flattened across both"; \
    : "roots). bootstrap.sh uses it as the 'universe' of built-ins: a volume skill"; \
    : "in the catalog but not in the keep-list is a de-listed built-in to prune;"; \
    : "agent-authored skills are never in the catalog, so are always preserved."; \
    for root in /opt/hermes-agent/skills /opt/hermes-agent/optional-skills; do \
      [ -d "$root" ] || continue; \
      find "$root" -name SKILL.md -printf '%h\n' | sed "s#^$root/##"; \
    done | sort -u > /opt/hermes-agent/skill-catalog-full.txt; \
    : "Build the curated sync source from the keep-list (both roots collapse into"; \
    : "one dir at the same category/skill paths)."; \
    clean=$(grep -vE '^[[:space:]]*(#|$)' /app/keep-skills.txt); \
    mkdir -p /app/curated-skills; \
    printf '%s\n' "$clean" | while IFS= read -r rel; do \
      [ -n "$rel" ] || continue; \
      for root in /opt/hermes-agent/skills /opt/hermes-agent/optional-skills; do \
        if [ -d "$root/$rel" ]; then \
          mkdir -p "/app/curated-skills/$rel"; \
          cp -a "$root/$rel/." "/app/curated-skills/$rel/"; \
          break; \
        fi; \
      done; \
    done; \
    echo "[curate-skills] catalog: $(wc -l < /opt/hermes-agent/skill-catalog-full.txt) built-ins | curated sync source:"; \
    find /app/curated-skills -name SKILL.md -printf '  %h\n' 2>/dev/null | sort
# skills_sync seeds ONLY this curated dir onto the volume.
ENV HERMES_BUNDLED_SKILLS=/app/curated-skills

# Install the Railway admin template. Clones at a pinned SHA (see
# HERMES_ADMIN_REF above), installs its Python deps, and drops .git. The
# server.py inside becomes our CMD; on boot it spawns `hermes gateway` +
# `hermes dashboard` and reverse-proxies them behind cookie auth.
RUN git clone https://github.com/praveen-ks-2001/hermes-agent-template.git /opt/hermes-admin && \
    cd /opt/hermes-admin && \
    git checkout ${HERMES_ADMIN_REF} && \
    rm -rf .git && \
    uv pip install --system --no-cache -r requirements.txt

# Points hermes at our pre-built TUI bundle. hermes's _make_tui_argv
# checks HERMES_TUI_DIR first: if dist/entry.js exists there, it skips
# the npm install/build entirely. Pre-building at image time avoids the
# 30-60s npm bootstrap that git-editable installs would otherwise trigger
# on first /chat connection.
ENV HERMES_TUI_DIR=/opt/hermes-agent/ui-tui

# Copy git-tracked architecture: AGENTS.md, SOUL.md, hermes.toml, mcp.json, skills/
WORKDIR /app
COPY hermes-config /app/hermes-config

# Core scripts: idempotent home provisioner + bootstrap. Downstream
# operationalization extends boot-time launches by dropping *.sh files into
# /app/bootstrap-overlay.d/ — bootstrap.sh sources any it finds after core
# setup (dir-missing and empty-dir are both no-ops).
COPY scripts/bootstrap.sh /app/bootstrap.sh
COPY scripts/seed-hermes-home.sh /app/seed-hermes-home.sh
RUN chmod +x /app/bootstrap.sh /app/seed-hermes-home.sh

# The /data mount comes from the Railway volume at runtime; don't VOLUME
# it here (Railway manages the mount itself). For local `docker run`, pass
# `-v <name>:/data` to materialize the same shape.

# tini wraps our bootstrap so it runs as PID 1's child. `-g` propagates
# signals to the whole process group so `docker stop` / Railway's SIGTERM
# cleanly terminates the entire tree, not just bootstrap.
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/app/bootstrap.sh"]

# Default command — launch the admin server from the pinned template clone.
# It binds the HTTP front door (cookie-auth gated by ADMIN_USERNAME /
# ADMIN_PASSWORD), spawns `hermes gateway` + `hermes dashboard` as managed
# subprocesses, and reverse-proxies them. bootstrap.sh `cd`s into
# /opt/hermes-admin first so Jinja2 finds its templates/ directory.
CMD ["python", "/opt/hermes-admin/server.py"]
