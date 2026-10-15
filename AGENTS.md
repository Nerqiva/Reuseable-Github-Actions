# AGENTS.md — Reusable GitHub Actions

Standing working agreement for anyone — human or agent — working **in this
repository**.

**Sources of truth:** this file (the invariants), [`README.md`](./README.md)
(the adoption manual), and the `github-actions` skill (the procedure for CI/CD,
images, GHCR, releases, and CalVer). **Load that skill before touching
`.github/workflows/`** — what follows is what must stay true; the skill is how
you carry it out.

## What this repo is

A **reference implementation of CI/CD workflows that other projects copy and
adapt**. It is not a shared library and not a dependency.

> **Rule — copy and adapt, never `uses:`.**
> No consuming repository may reference this repo via
> `uses: Nerqiva/Reuseable-Github-Actions/.github/workflows/...@main`. A
> `uses:` reference couples the consumer's release cadence to this repo's
> commits, breaks when the file moves or is refactored, and inherits breakage
> from a change nobody made. Copy the file, then own it.

Consumers record the adoption in their own `README.md` or `AGENTS.md`, stating
which parts were adapted.

## Where a rule belongs

Repeatable CI/CD procedure — a workflow, an image, a release, a version —
belongs in the **`github-actions` skill**, not here. Documenting steps in this
file is the wrong file: an invariant earns a line, a procedure earns a skill.
The global `AGENTS.md` states the rule in full; here it is scoped to this
repo's workflows.

## Hard rules

### Versioning — CalVer `vYYYY.MM.DD.MICRO`

- `YYYY.MM.DD` is the **commit date in UTC**, never run-time wall clock — a
  re-run of one commit must produce the same version.
- `MICRO` is the number of commits on that UTC day — what lets "publish every
  commit" coexist with "never overwrite an immutable tag". E.g. `v2026.10.14.3`.

### Tag mutability

> **Rule — exactly one mutable tag exists.**
> `latest` is **mutable**, is **GHCR-only**, and is the **only** tag that may
> be overwritten. CalVer tags and GitHub Releases are **immutable** and
> **never** replaced.

- Both workflows query GHCR / GitHub **first** and skip or fail when the version
  is taken: no `--clobber`, no `git tag -f`, no re-push over a taken tag.
- `latest` is pushed in the **same step** as the version tag, so it can never
  describe a different build than the tag beside it.
- A tag-triggered binary run must prove the pushed tag equals the CalVer version
  of its own commit before the collision guard counts for anything.
- Binary releases have **no `latest`** — a container-registry concept; binaries
  are addressed solely by CalVer version.

### Credentials

- The name is **`GITHUB_PERSONAL_ACCESS_TOKEN`** everywhere:
  `$GITHUB_PERSONAL_ACCESS_TOKEN` in a shell,
  `${{ secrets.GITHUB_PERSONAL_ACCESS_TOKEN }}` in a workflow — a shell
  variable is not readable as a workflow secret.
- GHCR login prefers `${{ secrets.GITHUB_TOKEN }}`: per-run, scoped, and
  granted `packages: write` by the workflow's own `permissions:` block.
- The personal token is only for what that built-in token lacks — cross-repo
  push, org-level settings.
- Never a literal credential in a file, diff, commit, log, or `echo`. A token in
  output is compromised: say so and rotate it.

### Git conventions

- Identity is fixed globally in `~/.gitconfig` — see *Repo identity note*.
- Every project is under Git — `git init` before making changes.
- Default remote owner is the **`Nerqiva`** org, never a personal account.
- Small, reviewable commits. No amend, no force-push unless explicitly asked.
- Do not create a GitHub remote, repository, or release unless explicitly asked.

### Editing conventions for this repo

- Workflows stay **parameterised**: `workflow_dispatch` inputs, with repository
  `Variables.*` as the fallback for push events, then the documented default.
  Never hardcode a project-specific value into a workflow here.
- `scripts/compute-calver.sh` is the **single source of truth for versioning**;
  both workflows shell out to it so image tag and release version cannot drift.
  Never inline the logic. A change to the version scheme is a change to this
  script *and* to the `CalVer` sections of `README.md`, in the same commit.
- Third-party actions stay pinned to a **version tag**, never `@main`:
  `actions/checkout@v7`, `actions/upload-artifact@v7`,
  `actions/download-artifact@v8`, `docker/setup-buildx-action@v4`,
  `docker/setup-qemu-action@v4`, `docker/login-action@v4`,
  `docker/metadata-action@v6`, `docker/build-push-action@v7`.
- **Never type a toggle as `type: boolean`.** GitHub expressions treat `false`
  as falsy, so `inputs.x || vars.X || '<default>'` falls through and an
  explicit "off" silently becomes a real push. Toggles are strings (`'true'` /
  `'false'`) that the workflow parses and validates.
- Workflow and script changes are documented in the same commit that makes
  them — `README.md` describes the contract, so a contract change is a
  `README.md` change.

## Repo identity note

The repository is
[`Nerqiva/Reuseable-Github-Actions`](https://github.com/Nerqiva/Reuseable-Github-Actions),
public. The spelling is deliberately as-is: **do not "correct" it in URLs or
image paths.** GHCR namespace paths must be lowercase, so the image reference
is written lowercase even though the repo name is not.

Commit author is the GitHub noreply address
`31291110+panicstack@users.noreply.github.com` — the standing identity
**globally** in `~/.gitconfig`, because GitHub rejects a push exposing a private
address into an unverified org. No per-repo override exists here; add none.

## Still open

- No `LICENSE` has been chosen. The owner must pick one before this repo is
  advertised for adoption. Do not invent one.