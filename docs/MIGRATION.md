# Migrating an existing instance onto Viajero 2.0

This runbook stands up a **fresh Viajero 2.0 service** and reconstitutes an **existing** traveler's
instance on top of the generic, user-agnostic codebase. It is deliberately principal-agnostic: every
private value (chat IDs, email account, home airport, expense inbox, OAuth project, tokens) is supplied
**out-of-band** at migration time and **never committed** — this repo is public.

> **New deployments** (no prior instance) don't need this — just deploy and let the `onboarding` skill
> capture the configuration floor on first contact. This document is only for **carrying an existing
> agent's data forward**.

## Model: generic in git, specific out-of-band

- **In git (this repo):** the durable, user-agnostic substrate — skills, references, `config.yaml`,
  `integrations.yaml` defaults, the `cron/jobs.json` templates, and the empty
  `hermes-config/memory/{MEMORY,USER,PEERS}.md` templates documenting the **16-key memory contract**.
- **Out-of-band (per operator, never git):** the filled `MEMORY.md`/`USER.md`, the per-principal
  `cron/jobs.json`, any `references/employers/<slug>.md`, and all secrets. Keep these in a local,
  gitignored working area (this project uses `.design/migration/`, excluded via `.git/info/exclude`).

## The 16-key memory contract

The fresh service is **provisional** until the configuration floor in `$HERMES_HOME/MEMORY.md` is
filled. Fill these keys **by exact name** (the cron jobs, references, and travel skills read them by
spelling). See `hermes-config/memory/MEMORY.md` for the authoritative template + per-key defaults:

`home_city`, `home_timezone` (IANA), `home_airport` (IATA; gates flight alerts), `travel_email_account`,
`travel_email_backend` (`himalaya` | `google_api`), `travel_bookings_label`, `travel_assignments_label`,
`travel_calendar_id`, `travel_notify_chat_id`, `travel_notify_channel`, `dm_chat_id`, `alert_lead_hours`,
`notify_locale`, `expense_receipt_inbox`, `employer_definition_file`, `assignment_type_codes`.

Secrets are **never** memory keys.

## Secrets: out-of-band bootstrap (env → volume)

`scripts/bootstrap.sh` seeds three credential files from environment variables on first boot, writing
them **raw** (`printf '%s'`, **no base64 decode**) and `chmod 600`. Therefore each env var must hold the
**raw file contents** — do **not** base64-encode them.

| Env var | Seeds (chmod 600) |
|---|---|
| `HERMES_AUTH_JSON_BOOTSTRAP` | `$HERMES_HOME/auth.json` |
| `HERMES_GOOGLE_TOKEN_BOOTSTRAP` | `$HERMES_HOME/google_token.json` |
| `HERMES_GOOGLE_CLIENT_SECRET_BOOTSTRAP` | `$HERMES_HOME/google_client_secret.json` |

Plain Railway env vars (not files): `OPENROUTER_API_KEY`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_HOME_CHANNEL`
(the operator DM chat id; equals `MEMORY.md dm_chat_id`), `LLM_MODEL`, and `HERMES_HOME` (= the
service's data dir, e.g. `/data/hermes`; must match `config.yaml data_dir`).

To pull credentials from an existing instance's volume, read each file **raw** over SSH and set it
verbatim as the matching env var (strip any SSH-tty carriage returns with `tr -d '\r'`). **Never** run
`git` against the old volume and **never** pull its `.git/config`.

## Hard rules

- **Public repo → no private values in git.** Filled memory, chat IDs, the email account, the OAuth
  project, and secrets stay out-of-band. Reference them by key, never by value, in issues/PRs.
- **The old volume's `repo/.../.git/config` may embed a Git credential/PAT — it must NOT travel.** The
  new service uses fresh `gh`/`git` auth.
- **Reuse the existing Google Cloud OAuth client — do not create a new project.** Migrate the two
  `google_*.json` files; calendar/Gmail scopes must match.
- **Stop the old gateway before starting the new one** if they share a bot token (avoids double replies).
- **Episodic history (`state.db`) is optional and usually skipped** — the durable facts live in
  semantic memory (`MEMORY.md`/`USER.md`); the fresh service builds its own `state.db`.

## Procedure

1. **Assemble the dataset (local, gitignored):** fill `MEMORY.md` + `USER.md` (home ROOT layout — not a
   `memories/` subdir), the per-principal `cron/jobs.json`, optional `references/employers/<slug>.md`,
   and `onboarding/state.json` with `onboarded: true` (so the pre-filled floor skips the onboarding
   gate). Shape each file to the corresponding `hermes-config/` template.
2. **Resolve gaps read-only** from the source instance (the email account, IANA timezone, any TMC/employer
   sender). Never touch the old `.git/config`.
3. **Configure the new service env:** the three `HERMES_*_BOOTSTRAP` vars (raw), `OPENROUTER_API_KEY`,
   `TELEGRAM_BOT_TOKEN`, `TELEGRAM_HOME_CHANNEL`, `LLM_MODEL`, `HERMES_HOME`. Do **not** set
   `HERMES_FORCE_RESEED`.
4. **Stop the old gateway.**
5. **First boot:** `bootstrap.sh` writes the secret files; `seed-hermes-home.sh` seeds the generic
   memory/integrations/cron (no-clobber) and `onboarding/state.json` (`onboarded: false`).
6. **Overlay the dataset:** copy the home-relative files over the generic seeds —
   `MEMORY.md`/`USER.md` to the home ROOT, `integrations.yaml`, `cron/jobs.json`,
   `references/employers/<slug>.md`, and `onboarding/state.json`. Use a plain copy — **not**
   `HERMES_FORCE_RESEED` (which would reseed the generic templates and discard the overlay).
7. **Verify:** `python3 $HERMES_HOME/skills/productivity/google-workspace/scripts/setup.py --check`
   → `AUTHENTICATED`; confirm `onboarding/state.json` is `onboarded: true`; confirm `MEMORY.md` has the
   floor filled with no placeholders; confirm the three credential files are mode `600`.
8. **Restart + smoke test:** trigger one reconciliation cycle → expect `[SILENT]` or a real reconcile;
   confirm channel routing (infra → operator DM; arrival alerts → logistics group only) and that idle
   cycles stay silent.

> Note: a personalized `MEMORY.md` will read as "memory divergence" against the generic
> `.seed-manifest.json` baseline — that is expected runtime drift, not a guardrail flag. Only
> `secret-on-disk` findings from the weekly divergence audit warrant action.
