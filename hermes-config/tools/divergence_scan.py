#!/usr/bin/env python3
"""divergence_scan.py — track how the running agent has modified ITSELF vs. git.

Viajero's identity is split in two (README, "Durability Story"):

  /app/hermes-config   (git-tracked baseline, baked into the image, read-only)
  $HERMES_HOME         (/data/hermes — the mutable volume the agent writes to)

On every boot `scripts/seed-hermes-home.sh` seeds the durable architecture onto
the volume (config.yaml, integrations.yaml, cron/jobs.json, references/, the
root memory templates MEMORY/USER/PEERS) no-clobber; the agent's skills load
read-only from the image via config.yaml `skills.external_dirs`. The agent then
mutates the volume: it authors NEW skills (coala-skill-induction), extends
references, edits config/cron, and fills the principal's memory. Nothing tells
the operator how far the volume has drifted from the durable codebase, nor which
of the agent's self-authored artifacts are generic enough to belong back in git.

This tool computes that divergence directly — the git baseline is physically
present at /app/hermes-config beside the volume, so no separate snapshot is
needed. It classifies every seeded file as unchanged / modified / agent-authored
/ missing, flags drift that warrants attention (a patched seed, a modified
durable skill, a SECRET written to disk — forbidden in anything promotable), and
surfaces *promotion candidates*: agent-authored skills/reference cards portable
enough to commit back. With --emit-patch it writes a `git apply`-able patch that
adds those candidates into hermes-config/, closing the learn → promote loop into
the durable codebase.

A candidate carrying a secret (API key, OAuth token, GitHub PAT, private key) is
flagged `secret-on-disk` and EXCLUDED from the emitted patch — a secret must
never be committed.

Zero third-party deps (stdlib only), matching the other tools/. Runs zero-arg on
the instance; pass --baseline/--home to diff a pulled-down volume locally.

Usage:
  divergence_scan.py [--baseline /app/hermes-config] [--home $HERMES_HOME]
                     [--emit-patch] [--format json|md]

Outputs:
  - Markdown report  -> $HOME/audits/divergence/<YYYY-MM-DD>.md
  - Patch (optional) -> $HOME/audits/divergence/<YYYY-MM-DD>.patch
  - JSON summary     -> stdout  (machine-readable; cron reads this to gate delivery)
  Human log lines go to stderr.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import difflib
import hashlib
import json
import os
import re
import sys
from typing import Optional

# ---------------------------------------------------------------------------
# Categories. references is a recursive tree (git references/ -> volume
# references/). The principal's memory lives as THREE files at the home ROOT
# (MEMORY.md / USER.md / PEERS.md), seeded from the git templates in
# hermes-config/memory/ — handled separately (MEMORY_FILES) as informational,
# never-promoted single files. config files are single files at the root. cron
# is handled apart (its JSON carries volatile run-state normalized out).
# skills are handled separately (scan_skills) — they load read-only from the
# image via skills.external_dirs and the volume mixes runtime-curated built-ins
# with agent augmentation, so a plain baseline<->volume diff doesn't apply.
# ---------------------------------------------------------------------------
TREE_CATEGORIES = [
    ("references", "references", "references"),
]

# The principal's memory context files at the home ROOT. (home filename,
# baseline-relative path under CONFIG_DIR). Informational only — per-principal
# state, expected to fill in, NEVER a promotion candidate.
MEMORY_FILES = [
    ("MEMORY.md", "memory/MEMORY.md"),
    ("USER.md", "memory/USER.md"),
    ("PEERS.md", "memory/PEERS.md"),
]

# Runtime built-in skill catalogs the Hermes runtime ships + curates onto the
# volume (skills_sync / skills_hub). Skills matching these are runtime-provided,
# not agent self-modification — excluded from agent-authored/promotion.
DEFAULT_RUNTIME_SKILL_DIRS = [
    "/opt/hermes-agent/skills",
    "/opt/hermes-agent/optional-skills",
]
# Full PRE-prune runtime catalog snapshotted by the Dockerfile before curation.
# A volume skill in this list but absent from the (post-prune) runtime dirs above
# is a DE-LISTED built-in — still runtime-provided, NOT agent self-modification.
# Without this, such skills look agent-authored (false promotion candidates) on a
# volume that hasn't yet rebooted into the reconciling bootstrap. Optional: absent
# on older images, in which case classification falls back to the runtime dirs.
DEFAULT_RUNTIME_SKILL_CATALOG = "/opt/hermes-agent/skill-catalog-full.txt"

FILE_CATEGORIES = [
    ("config", "config.yaml", "config.yaml"),
    ("config", "integrations.yaml", "integrations.yaml"),
]

# cron job fields that change every run — normalized out so jobs.json isn't
# perpetually "dirty". Everything else (prompt/schedule/skills/enabled/deliver)
# is semantic drift worth reporting.
CRON_VOLATILE_FIELDS = {
    "state", "paused_at", "paused_reason", "created_at", "next_run_at",
    "last_run_at", "last_status", "last_error", "last_delivery_error",
}

# Secrets are forbidden on disk in anything promotable (README security rules:
# API keys / OAuth tokens / a GitHub PAT must never be committed). Finding one in
# a candidate file is high-signal drift; the candidate is excluded from the patch.
SECRET_PATTERNS = [
    ("anthropic-key", re.compile(r"\bsk-ant-[A-Za-z0-9_-]{20,}")),
    ("openrouter-key", re.compile(r"\bsk-or-v1-[A-Za-z0-9]{16,}")),
    ("openai-key", re.compile(r"\bsk-[A-Za-z0-9]{20,}")),
    ("github-pat", re.compile(r"\b(?:ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,})")),
    ("aws-key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("telegram-token", re.compile(r"\b\d{8,10}:[A-Za-z0-9_-]{35}\b")),
    ("slack-token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}")),
    ("oauth-token-json", re.compile(
        r"\"(?:refresh_token|client_secret|access_token)\"\s*:\s*\"[^\"]{8,}\"")),
    ("private-key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----")),
]

# Conservative personal-data markers — a skill that hardcodes these is probably
# not portable. Non-blocking: emitted as a warning beside the candidate so the
# operator decides. (The references scaffold is principal-agnostic by doctrine.)
PII_PATTERNS = [
    ("email", re.compile(r"\b[\w.+-]+@[\w-]+\.[\w.-]+\b")),
    ("named-subject", re.compile(r"\b(?:my name is|the user's name|the principal's name)\b", re.I)),
]

TEXT_EXTS = {".md", ".markdown", ".txt", ".yaml", ".yml", ".json"}


def log(msg: str) -> None:
    print(f"[divergence] {msg}", file=sys.stderr)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_bytes(path: str) -> Optional[bytes]:
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except (OSError, IOError):
        return None


def read_text(path: str) -> Optional[str]:
    data = read_bytes(path)
    if data is None:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("utf-8", "replace")


# ---------------------------------------------------------------------------
# Baseline abstraction: a directory (primary) or a seed manifest (fallback when
# /app/hermes-config is absent, e.g. running locally against a pulled volume).
# Keys are HOME-relative paths; memory templates map memory/<X> -> root <X>.
# ---------------------------------------------------------------------------
class DirBaseline:
    """Compare against the live git-tracked dir at --baseline."""

    HOME_TO_BASELINE = {"skills": "skills", "references": "references"}

    def __init__(self, root: str):
        self.root = root

    def kind(self) -> str:
        return f"dir:{self.root}"

    def _baseline_subdir(self, home_subdir: str) -> str:
        return self.HOME_TO_BASELINE.get(home_subdir, home_subdir)

    def tree_files(self, home_subdir: str) -> dict:
        """relpath-within-subdir -> sha256, for every file in the baseline tree."""
        sub = os.path.join(self.root, self._baseline_subdir(home_subdir))
        out: dict = {}
        if not os.path.isdir(sub):
            return out
        for dirpath, _dirs, files in os.walk(sub):
            for name in files:
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, sub)
                data = read_bytes(full)
                if data is not None:
                    out[rel] = sha256_bytes(data)
        return out

    def tree_text(self, home_subdir: str, rel: str) -> Optional[str]:
        sub = os.path.join(self.root, self._baseline_subdir(home_subdir))
        return read_text(os.path.join(sub, rel))

    def file_sha(self, name: str) -> Optional[str]:
        data = read_bytes(os.path.join(self.root, name))
        return sha256_bytes(data) if data is not None else None

    def file_text(self, name: str) -> Optional[str]:
        return read_text(os.path.join(self.root, name))

    # Memory templates: home root file <name> comes from CONFIG_DIR/memory/<name>.
    def mem_sha(self, name: str) -> Optional[str]:
        return self.file_sha(os.path.join("memory", name))

    def mem_text(self, name: str) -> Optional[str]:
        return self.file_text(os.path.join("memory", name))

    def cron_text(self) -> Optional[str]:
        return read_text(os.path.join(self.root, "cron", "jobs.json"))


class ManifestBaseline:
    """Fallback: sha-only baseline from $HOME/.seed-manifest.json.

    Detects unchanged/modified/authored but cannot produce content diffs for
    *modified* files (the seed content isn't stored) — those patches are skipped.
    Memory templates are keyed at the home ROOT (MEMORY.md), matching the seed.
    """

    def __init__(self, manifest: dict):
        self.commit = manifest.get("commit")
        self._files = manifest.get("files", {})  # home-relpath -> sha

    def kind(self) -> str:
        return f"manifest@{self.commit or 'unknown'}"

    def tree_files(self, home_subdir: str) -> dict:
        prefix = home_subdir.rstrip("/") + "/"
        out = {}
        for rel, sha in self._files.items():
            if rel.startswith(prefix):
                out[rel[len(prefix):]] = sha
        return out

    def tree_text(self, home_subdir: str, rel: str) -> Optional[str]:
        return None  # content not retained in the manifest

    def file_sha(self, name: str) -> Optional[str]:
        return self._files.get(name)

    def file_text(self, name: str) -> Optional[str]:
        return None

    def mem_sha(self, name: str) -> Optional[str]:
        return self._files.get(name)  # manifest keys memory at root

    def mem_text(self, name: str) -> Optional[str]:
        return None

    def cron_text(self) -> Optional[str]:
        return None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def home_tree_files(home: str, home_subdir: str) -> dict:
    sub = os.path.join(home, home_subdir)
    out: dict = {}
    if not os.path.isdir(sub):
        return out
    for dirpath, _dirs, files in os.walk(sub):
        for name in files:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, sub)
            data = read_bytes(full)
            if data is not None:
                out[rel] = sha256_bytes(data)
    return out


def has_frontmatter(text: Optional[str]) -> bool:
    """True if the doc opens with a YAML frontmatter block carrying name+description."""
    if not text or not text.startswith("---"):
        return False
    end = text.find("\n---", 3)
    if end == -1:
        return False
    block = text[3:end]
    return bool(re.search(r"^\s*name\s*:", block, re.M)) and \
        bool(re.search(r"^\s*description\s*:", block, re.M))


def find_secrets(text: Optional[str]) -> list:
    """Return a de-duplicated list of secret *labels* found in the text."""
    if not text:
        return []
    hits = []
    for label, pat in SECRET_PATTERNS:
        if pat.search(text) and label not in hits:
            hits.append(label)
    return hits


def find_pii(text: Optional[str]) -> list:
    if not text:
        return []
    hits = []
    for label, pat in PII_PATTERNS:
        if pat.search(text):
            hits.append(label)
    return hits


def strip_cron_volatile(jobs_text: Optional[str]) -> dict:
    """id -> normalized job dict (volatile run-state removed). {} on parse fail."""
    if not jobs_text:
        return {}
    try:
        doc = json.loads(jobs_text)
    except (json.JSONDecodeError, ValueError):
        return {}
    out = {}
    for job in doc.get("jobs", []):
        if not isinstance(job, dict):
            continue
        norm = {k: v for k, v in job.items() if k not in CRON_VOLATILE_FIELDS}
        rep = norm.get("repeat")
        if isinstance(rep, dict):
            norm["repeat"] = {k: v for k, v in rep.items() if k != "completed"}
        out[job.get("id") or f"<anon-{len(out)}>"] = norm
    return out


# ---------------------------------------------------------------------------
# Patch construction (git apply-able)
# ---------------------------------------------------------------------------
REPO_PREFIX = "hermes-config"  # patches target the repo layout, not the volume


def _repo_path(home_subdir: str, rel: str) -> str:
    # root memory files (MEMORY.md/…) came from memory/ in the repo
    if home_subdir == "memory":
        return f"{REPO_PREFIX}/memory/{rel}"
    return f"{REPO_PREFIX}/{home_subdir}/{rel}"


def patch_new_file(repo_path: str, new_text: str) -> str:
    lines = new_text.splitlines(keepends=True)
    out = [f"diff --git a/{repo_path} b/{repo_path}\n",
           "new file mode 100644\n", "--- /dev/null\n", f"+++ b/{repo_path}\n"]
    if not lines:
        return "".join(out)
    out.append(f"@@ -0,0 +1,{len(lines)} @@\n")
    for ln in lines:
        if ln.endswith("\n"):
            out.append("+" + ln)
        else:
            out.append("+" + ln + "\n")
            out.append("\\ No newline at end of file\n")
    return "".join(out)


def patch_modified_file(repo_path: str, old_text: str, new_text: str) -> str:
    old = old_text.splitlines(keepends=True)
    new = new_text.splitlines(keepends=True)
    body = "".join(difflib.unified_diff(
        old, new, fromfile=f"a/{repo_path}", tofile=f"b/{repo_path}", lineterm="\n"))
    return f"diff --git a/{repo_path} b/{repo_path}\n" + body


# ---------------------------------------------------------------------------
# Skills (runtime-aware). The volume's skills/ holds runtime-curated built-ins
# (skills_sync/skills_hub) + agent-authored augmentation; our durable skills load
# read-only from the image via skills.external_dirs and are NOT on the volume. So
# we classify per skill-unit (a dir containing SKILL.md), not by baseline<->volume
# file diff: runtime-provided (in a runtime catalog) · durable (matches the image
# baseline; modified = an in-deploy edit that won't persist) · agent-authored
# (genuine augmentation -> promotion candidate).
# ---------------------------------------------------------------------------
def _skill_dirs(root: str) -> set:
    """rel-dirs (relative to a skills root) that contain a SKILL.md."""
    out = set()
    if not os.path.isdir(root):
        return out
    for dirpath, _dirs, files in os.walk(root):
        if "SKILL.md" in files:
            rel = os.path.relpath(dirpath, root)
            if rel != ".":
                out.add(rel)
    return out


def _skill_dir_files(skills_root: str, rel_dir: str) -> list:
    """all file relpaths (relative to skills_root) under a skill dir."""
    base = os.path.join(skills_root, rel_dir)
    out = []
    for dirpath, _dirs, files in os.walk(base):
        for name in files:
            full = os.path.join(dirpath, name)
            out.append(os.path.relpath(full, skills_root))
    return sorted(out)


def load_runtime_catalog(path: str) -> set:
    """Full pre-prune runtime skill catalog (category/skill per line). Empty if absent."""
    try:
        with open(path, encoding="utf-8") as fh:
            return {ln.strip() for ln in fh if ln.strip()}
    except OSError:
        return set()


def scan_skills(baseline, home: str, runtime_roots: list, want_patch: bool,
                runtime_catalog: set = frozenset()) -> dict:
    home_skills = os.path.join(home, "skills")
    counts = {"unchanged": 0, "modified": 0, "agent-authored": 0,
              "runtime-provided": 0}
    rows, candidates, flags, patches = [], [], [], []

    durable_dirs = {os.path.dirname(rel) for rel in baseline.tree_files("skills")
                    if os.path.basename(rel) == "SKILL.md"}
    runtime_dirs = set()
    for r in runtime_roots:
        runtime_dirs |= _skill_dirs(r)

    for rel_dir in sorted(_skill_dirs(home_skills)):
        path = f"skills/{rel_dir}"
        # In the live runtime dirs, or a de-listed built-in (full pre-prune
        # catalog) — either way runtime-provided, not agent self-modification.
        if rel_dir in runtime_dirs or rel_dir in runtime_catalog:
            counts["runtime-provided"] += 1
            continue

        cur_text = read_text(os.path.join(home_skills, rel_dir, "SKILL.md"))
        if rel_dir in durable_dirs:
            base_text = baseline.tree_text("skills", f"{rel_dir}/SKILL.md")
            if base_text is not None and cur_text == base_text:
                counts["unchanged"] += 1
                continue
            counts["modified"] += 1
            rows.append({"path": path, "status": "modified-durable"})
            flags.append({"type": "modified-durable", "path": path,
                          "detail": "a durable (image) skill was edited on the "
                          "volume — won't survive redeploy; revert or promote"})
            continue

        # agent-authored augmentation
        counts["agent-authored"] += 1
        rows.append({"path": path, "status": "agent-authored"})
        secrets = find_secrets(cur_text)
        warnings = []
        if not has_frontmatter(cur_text):
            warnings.append("no valid frontmatter (name/description)")
        warnings.extend(find_pii(cur_text))
        if secrets:
            flags.append({"type": "secret-on-disk", "path": f"{path}/SKILL.md",
                          "detail": "secret(s) detected (" + ", ".join(secrets) +
                          ") — excluded from promotion; never commit a secret"})
        # promotable only with valid frontmatter AND no secret
        if has_frontmatter(cur_text) and not secrets:
            cand = {"path": path, "repo_path": f"{REPO_PREFIX}/skills/{rel_dir}",
                    "category": "skills", "status": "agent-authored",
                    "warnings": warnings}
            candidates.append(cand)
            if want_patch:
                for frel in _skill_dir_files(home_skills, rel_dir):
                    ftext = read_text(os.path.join(home_skills, frel))
                    if ftext is not None and not find_secrets(ftext):
                        patches.append(patch_new_file(
                            f"{REPO_PREFIX}/skills/{frel}", ftext))

    return {"counts": counts, "rows": rows, "candidates": candidates,
            "flags": flags, "patches": patches}


# ---------------------------------------------------------------------------
# Scan
# ---------------------------------------------------------------------------
def scan(baseline, home: str, want_patch: bool, runtime_roots: list,
         runtime_catalog: set = frozenset()) -> dict:
    counts: dict = {}
    sections: dict = {}
    candidates: list = []
    flags: list = []
    patches: list = []

    # --- skills (runtime-aware, handled separately) ------------------------
    sk = scan_skills(baseline, home, runtime_roots, want_patch, runtime_catalog)
    counts["skills"] = sk["counts"]
    sections["skills"] = sk["rows"]
    candidates.extend(sk["candidates"])
    flags.extend(sk["flags"])
    patches.extend(sk["patches"])

    # --- tree categories: references ---------------------------------------
    for label, _bsub, home_subdir in TREE_CATEGORIES:
        base = baseline.tree_files(home_subdir)
        cur = home_tree_files(home, home_subdir)
        rows = []
        c = {"unchanged": 0, "modified": 0, "agent-authored": 0, "missing": 0}
        for rel in sorted(set(base) | set(cur)):
            if rel in base and rel in cur:
                status = "unchanged" if base[rel] == cur[rel] else "modified"
            elif rel in cur:
                status = "agent-authored"
            else:
                status = "missing"
            c[status] += 1
            rows.append({"path": f"{home_subdir}/{rel}", "status": status,
                         "rel": rel, "home_subdir": home_subdir, "label": label})
        counts[label] = counts.get(label, {"unchanged": 0, "modified": 0,
                                            "agent-authored": 0, "missing": 0})
        for k, v in c.items():
            counts[label][k] += v
        sections.setdefault(label, []).extend(rows)

        # classify each non-trivial row
        for row in rows:
            if row["status"] == "unchanged":
                continue
            rel, hsub = row["rel"], row["home_subdir"]
            cur_text = read_text(os.path.join(home, hsub, rel))
            repo_path = _repo_path(hsub, rel)

            if row["status"] == "missing":
                flags.append({"type": "deleted-seed", "path": row["path"],
                              "detail": "seed file absent on the volume"})
                continue

            secrets = find_secrets(cur_text)
            if secrets:
                flags.append({"type": "secret-on-disk", "path": row["path"],
                              "detail": "secret(s) detected (" + ", ".join(secrets) +
                              ") — excluded from promotion; never commit a secret"})
            if row["status"] == "modified":
                flags.append({"type": "modified-seed", "path": row["path"],
                              "detail": "diverges from the git-tracked seed"})

            # promotion eligibility: agent-authored/improved references with no secret
            is_candidate = not secrets
            if is_candidate:
                cand = {"path": row["path"], "repo_path": repo_path,
                        "category": label, "status": row["status"],
                        "warnings": find_pii(cur_text)}
                candidates.append(cand)
                if want_patch and cur_text is not None:
                    if row["status"] == "agent-authored":
                        patches.append(patch_new_file(repo_path, cur_text))
                    else:  # modified — needs seed content to diff
                        old = baseline.tree_text(hsub, rel)
                        if old is not None:
                            patches.append(patch_modified_file(repo_path, old, cur_text))
                        else:
                            cand["warnings"] = cand["warnings"] + [
                                "patch skipped: baseline content unavailable"]

    # --- memory (root MEMORY/USER/PEERS — informational, never promoted) ---
    mem_rows = []
    mc = {"unchanged": 0, "modified": 0, "agent-authored": 0, "missing": 0}
    for hname, _brel in MEMORY_FILES:
        bsha = baseline.mem_sha(hname)
        cur_data = read_bytes(os.path.join(home, hname))
        csha = sha256_bytes(cur_data) if cur_data is not None else None
        if bsha is None and csha is None:
            continue
        if bsha is not None and csha is not None:
            status = "unchanged" if bsha == csha else "modified"
        elif csha is not None:
            status = "agent-authored"
        else:
            status = "missing"
        mc[status] += 1
        if status != "unchanged":
            mem_rows.append({"path": hname, "status": status})
            # A secret in the principal's memory is a hygiene flag (not promoted).
            secrets = find_secrets(read_text(os.path.join(home, hname)))
            if secrets:
                flags.append({"type": "secret-on-disk", "path": hname,
                              "detail": "secret(s) in memory (" + ", ".join(secrets) +
                              ") — move to env/secrets, never leave on disk"})
    counts["memory"] = mc
    sections["memory"] = mem_rows

    # --- config files ------------------------------------------------------
    cfg_rows = []
    cc = {"unchanged": 0, "modified": 0, "agent-authored": 0, "missing": 0}
    for _label, bname, hname in FILE_CATEGORIES:
        bsha = baseline.file_sha(bname)
        cur_data = read_bytes(os.path.join(home, hname))
        csha = sha256_bytes(cur_data) if cur_data is not None else None
        if bsha is None and csha is None:
            continue
        if bsha is not None and csha is not None:
            status = "unchanged" if bsha == csha else "modified"
        elif csha is not None:
            status = "agent-authored"
        else:
            status = "missing"
        cc[status] += 1
        cfg_rows.append({"path": hname, "status": status})
    counts["config"] = cc
    sections["config"] = cfg_rows

    # --- cron (normalized) -------------------------------------------------
    base_cron_raw = baseline.cron_text()
    cron_rows = []
    crc = {"unchanged": 0, "modified": 0, "agent-authored": 0, "missing": 0}
    if base_cron_raw is None:
        # manifest-only baseline can't supply cron content — skip rather than
        # report every job as agent-authored noise.
        counts["cron"] = crc
        sections["cron"] = cron_rows
        return {"counts": counts, "sections": sections, "candidates": candidates,
                "flags": flags, "patches": patches}
    base_jobs = strip_cron_volatile(base_cron_raw)
    cur_jobs = strip_cron_volatile(read_text(os.path.join(home, "cron", "jobs.json")))
    for jid in sorted(set(base_jobs) | set(cur_jobs)):
        if jid in base_jobs and jid in cur_jobs:
            status = "unchanged" if base_jobs[jid] == cur_jobs[jid] else "modified"
        elif jid in cur_jobs:
            status = "agent-authored"
        else:
            status = "missing"
        crc[status] += 1
        if status != "unchanged":
            cron_rows.append({"path": f"cron/jobs.json#{jid}", "status": status})
            if status in ("modified", "agent-authored"):
                flags.append({"type": "cron-drift", "path": f"cron/jobs.json#{jid}",
                              "detail": f"job {status} vs seed (run-state ignored)"})
    counts["cron"] = crc
    sections["cron"] = cron_rows

    return {"counts": counts, "sections": sections, "candidates": candidates,
            "flags": flags, "patches": patches}


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
def render_md(result: dict, baseline_kind: str, commit: str, today: str) -> str:
    counts = result["counts"]
    cand = result["candidates"]
    flags = result["flags"]
    out = [f"# Self-modification divergence — {today}", "",
           f"- Baseline: `{baseline_kind}` (commit `{commit}`)",
           f"- Promotion candidates: **{len(cand)}**",
           f"- Guardrail flags: **{len(flags)}**", "",
           "## Summary", "", "| Category | unchanged | modified | agent-authored | missing |",
           "| --- | --: | --: | --: | --: |"]
    for label in ["skills", "references", "config", "cron", "memory"]:
        c = counts.get(label)
        if not c:
            continue
        out.append(f"| {label} | {c.get('unchanged', 0)} | {c.get('modified', 0)} | "
                   f"{c.get('agent-authored', 0)} | {c.get('missing', 0)} |")
    rp = counts.get("skills", {}).get("runtime-provided", 0)
    out += ["", f"_Skills: {rp} runtime-provided (Hermes built-ins) excluded as "
            "not agent-authored._", ""]

    if flags:
        out += ["## ⚠️ Guardrail flags", ""]
        for f in flags:
            out.append(f"- **{f['type']}** — `{f['path']}`: {f['detail']}")
        out.append("")

    out += ["## Promotion candidates (eligible for the durable repo)", ""]
    if cand:
        for c in cand:
            warn = f" — ⚠️ {', '.join(c['warnings'])}" if c["warnings"] else ""
            out.append(f"- `{c['path']}` → `{c['repo_path']}` "
                       f"({c['category']}, {c['status']}){warn}")
        out += ["", "Review the emitted `.patch`, then `git apply` it inside the repo "
                "and commit to promote these into `hermes-config/`."]
    else:
        out.append("_None — no agent-authored, portable artifacts this scan._")
    out.append("")

    # per-category detail of what changed
    out += ["## Detail", ""]
    for label in ["skills", "references", "config", "cron", "memory"]:
        rows = [r for r in result["sections"].get(label, []) if r["status"] != "unchanged"]
        if not rows:
            continue
        out.append(f"### {label}")
        for r in rows:
            out.append(f"- `{r['path']}` — {r['status']}")
        out.append("")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def load_baseline(baseline_dir: str, home: str):
    if os.path.isdir(baseline_dir):
        return DirBaseline(baseline_dir), None
    manifest_path = os.path.join(home, ".seed-manifest.json")
    text = read_text(manifest_path)
    if text:
        try:
            man = json.loads(text)
            log(f"baseline dir absent; falling back to {manifest_path}")
            b = ManifestBaseline(man)
            return b, man.get("commit")
        except (json.JSONDecodeError, ValueError):
            pass
    return None, None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Track agent self-modification vs. git baseline.")
    ap.add_argument("--baseline", default=os.environ.get("HERMES_BASELINE_DIR",
                                                          "/app/hermes-config"))
    ap.add_argument("--home", default=os.environ.get("HERMES_HOME", "/data/hermes"))
    ap.add_argument("--emit-patch", action="store_true")
    ap.add_argument("--format", choices=["json", "md"], default="json")
    ap.add_argument("--runtime-skills-dir", action="append", metavar="DIR",
                    help="Hermes runtime built-in skill catalog (repeatable). "
                    "Skills found here are 'runtime-provided', not agent-authored. "
                    f"Default: {','.join(DEFAULT_RUNTIME_SKILL_DIRS)}")
    ap.add_argument("--runtime-skills-catalog", metavar="FILE",
                    default=DEFAULT_RUNTIME_SKILL_CATALOG,
                    help="Full pre-prune runtime skill catalog file. Entries here "
                    "are 'runtime-provided' even if de-listed by curation. "
                    f"Default: {DEFAULT_RUNTIME_SKILL_CATALOG} (skipped if absent).")
    args = ap.parse_args(argv)
    runtime_roots = args.runtime_skills_dir or DEFAULT_RUNTIME_SKILL_DIRS
    runtime_catalog = load_runtime_catalog(args.runtime_skills_catalog)

    baseline, man_commit = load_baseline(args.baseline, args.home)
    if baseline is None:
        log(f"FATAL: no baseline — '{args.baseline}' missing and no "
            f"{args.home}/.seed-manifest.json fallback.")
        return 2
    if not os.path.isdir(args.home):
        log(f"FATAL: home '{args.home}' is not a directory.")
        return 2

    commit = os.environ.get("RAILWAY_GIT_COMMIT_SHA") or man_commit or "unknown"
    today = _dt.date.today().isoformat()

    result = scan(baseline, args.home, args.emit_patch, runtime_roots,
                  runtime_catalog)

    report_dir = os.path.join(args.home, "audits", "divergence")
    os.makedirs(report_dir, exist_ok=True)
    md = render_md(result, baseline.kind(), commit, today)
    report_path = os.path.join(report_dir, f"{today}.md")
    with open(report_path, "w", encoding="utf-8") as fh:
        fh.write(md + "\n")
    log(f"wrote report -> {report_path}")

    patch_path = None
    if args.emit_patch and result["patches"]:
        patch_path = os.path.join(report_dir, f"{today}.patch")
        with open(patch_path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(result["patches"]).rstrip("\n") + "\n")
        log(f"wrote patch  -> {patch_path} ({len(result['patches'])} file(s))")

    summary = {
        "generated_at": today,
        "baseline": baseline.kind(),
        "baseline_commit": commit,
        "counts": result["counts"],
        "promotion_candidates": [
            {"path": c["path"], "repo_path": c["repo_path"],
             "category": c["category"], "warnings": c["warnings"]}
            for c in result["candidates"]],
        "guardrail_flags": result["flags"],
        "report_path": report_path,
        "patch_path": patch_path,
        "noteworthy": bool(result["candidates"] or result["flags"]),
    }

    if args.format == "md":
        print(md)
    else:
        print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
