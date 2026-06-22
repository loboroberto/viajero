---
name: coala-divergence-audit
description: >
  Audit how you have modified YOURSELF on the volume vs. the git-tracked durable
  codebase, and surface what should be committed back. Reports agent-authored
  skills / reference cards (promotion candidates), flags drift (a patched seed, a
  modified durable skill, a secret written to disk), and emits a git-apply-able
  patch. Trigger phrases: what have you changed about yourself, divergence audit,
  self-modification report, what should we commit back to git, what have you
  learned that belongs in the repo, show drift from the baseline.
version: 1.0.0
tags: [coala, meta, learning, procedural-memory, durability]
---

# Divergence Audit (CoALA §8 — auditing the self-modification surface)

Your identity is split (README, "Durability Story"): the **durable codebase** is
git-tracked and baked into the image at `/app/hermes-config`; the **volume**
(`$HERMES_HOME`, `/data/hermes`) is where you write your learning actions —
authored/patched skills (`coala-skill-induction`), extended references, config/cron
edits, and the principal's memory (`MEMORY.md`, `USER.md`, `PEERS.md` at the home
root).

Those volume writes never flow back to git on their own. This skill makes the
divergence **visible** and turns the best of it into a commit the operator can
review — closing the learn → promote loop into the durable codebase. It is the
concrete mechanism behind "mirror shareable skills to git" in `coala-skill-induction`.

> **Engine ships separately.** The scan tool `divergence_scan.py` (and its
> `~/.hermes/tools/` wiring + `.seed-manifest.json` baseline) lands with the
> seed/bootstrap work in a later issue. Until then this card documents the
> procedure; the command below activates once the tool is in place.

## When to Use

- The operator asks what you've changed about yourself, or what should be
  committed back to the repo.
- After a stretch of autonomous work (new skills, reference edits) — to propose
  durable promotions before they're forgotten on the volume.
- As a periodic guardrail (also run by the `self-divergence-audit` cron job):
  catch a patched seed, a modified durable skill, or — most important — a
  **secret accidentally written to disk** in a promotable artifact (an API key,
  OAuth token, or GitHub PAT must never be committed; see the security rules).

## Procedure

### 1. Run the scan
```
python3 ~/.hermes/tools/divergence_scan.py --emit-patch
```
Defaults compare the live baseline at `/app/hermes-config` against `$HERMES_HOME`.
It prints a JSON summary to stdout and writes:
- a Markdown report → `$HERMES_HOME/audits/divergence/<date>.md`
- a `git apply`-able patch (if there are candidates) → `…/<date>.patch`

### 2. Read the JSON summary
Key fields:
- `counts` — per category (skills / references / config / cron / memory): how many
  unchanged / modified / agent-authored / missing.
- `promotion_candidates` — agent-authored or improved artifacts portable enough for
  the repo. Each has a `repo_path` (where it would land) and `warnings` (e.g.
  possible personal data — review before promoting).
- `guardrail_flags` — drift that warrants attention:
  - `modified-seed` — a git-seeded file (references/config) was edited on the volume.
  - `modified-durable` — a durable skill (loaded read-only from the image via
    `skills.external_dirs`) was edited on the volume. It won't survive redeploy —
    either revert it, or promote the change into `hermes-config/skills/`.
  - `secret-on-disk` — an API key / OAuth token / GitHub PAT / `*token*.json`-style
    credential was found in a promotable artifact (**security violation** — fix it:
    secrets live in env / the runtime `secrets/` area, never in git-tracked or
    promotable files; never commit one).
  - `cron-drift` / `deleted-seed` — schedule/prompt changed, or a seed removed.
- Skills shipped by the Hermes runtime (`/opt/hermes-agent/{skills,optional-skills}`)
  are reported as **runtime-provided** and excluded from promotion — they are not
  your self-modification. Only genuinely agent-authored skills are candidates.
- `noteworthy` — true if there is anything to report.

### 3. Summarize for the operator
Lead with the headline (`N promotion candidates, M guardrail flags`). Then:
- List promotion candidates with their `repo_path`, noting any `warnings`.
- Surface guardrail flags plainly — especially `secret-on-disk`, which you should
  offer to fix immediately (strip the credential; move it to env / `secrets/`).
- Point at the report and patch paths. Memory changes (`MEMORY.md` / `USER.md` /
  `PEERS.md`) are informational only (per-principal, expected) — never promotion
  candidates.

### 4. Promote (operator-gated)
Promotion crosses the volume → git boundary, so **never auto-commit**. Present the
patch and let the operator pull it down and `git apply` it in the repo:
```
git apply audits/divergence/<date>.patch   # run in the repo checkout, then review + commit
```
For a skill candidate, this is exactly the "mirror to git" step of
`coala-skill-induction` made concrete.

### 5. Log the audit
Append an episodic note: "Ran divergence audit on <date>: <N> candidates, <M>
flags; proposed promoting <…>." This keeps the self-modification surface auditable
(AGENTS.md §8).

## Pitfalls

- **Treating candidates as auto-merge.** They are *proposals*. The volume → git
  promotion is the operator's call; you surface and emit, you don't commit.
- **Ignoring `warnings`.** A skill that hardcodes the principal's data (chat IDs,
  email, trips) is not portable — generalize it before promoting, or leave it on
  the volume.
- **Dismissing `secret-on-disk`.** It is a real security breach, not noise. Strip
  the credential immediately; it must never reach git.
- **Confusing cron run-state with drift.** The tool normalizes volatile fields
  (`last_run_at`, etc.); only real schedule/prompt edits surface.

## Verification

- The scan exits 0 and writes a report under `audits/divergence/`.
- Every `promotion_candidates[].repo_path` points under `hermes-config/`.
- If a patch was emitted, `git apply --check <patch>` succeeds in the repo.
- No `secret-on-disk` flag remains unaddressed.
- An episodic note records the audit.
