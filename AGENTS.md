# AGENTS.md — Reusable GitHub Actions

Standing working agreement for anyone — human or agent — working **in** this
repository.

**Sources of truth:** this file, [`README.md`](./README.md) (the adoption
manual), and the `github-actions` skill (the procedure for CI/CD, images, GHCR,
releases, and CalVer). Load the skill before touching anything under
`.github/workflows/`.

## What this repo is

A **reference implementation of CI/CD workflows that other projects copy and
adapt**. It is not a shared library and not a dependency.

> **Rule — copy and adapt, never `uses:`.**
> No consuming repository may reference this repo via
> `uses: Nerqiva/Reuseable-Github-Actions/.github/workflows/...@main`. A
> `uses:` reference couples the consumer's release cadence to this repo's
> commits, breaks when the file moves or is refactored, and inherits breakage
> from a change nobody made. Copy the file, then own it.

Consumers are expected to record the adoption in their own `README.md` or
`AGENTS.md` and state which parts were adapted.

## Hard rules

### Versioning — CalVer `vYYYY.MM.DD.MICRO`

- `YYYY.MM.DD` is the **commit date in UTC**, never the run-time wall clock.
  A re-run of the same commit must produce the same version; if it changes,
  the date was taken from run time and the versioning is wrong.
- `MICRO` is the number of commits on that UTC day. It is what lets "publish
  every commit" coexist with "never overwrite an immutable tag". Dropping it
  makes the second commit of the day collide and fail.
- Example: `v2026.10.14.3`.

### Tag mutability

> **Rule — exactly one mutable tag exists.**
> `latest` is **mutable**, is **GHCR-only**, and is the **only** tag that may
> be overwritten. CalVer version tags and GitHub Releases are **immutable** and
> are **never** replaced.

- Both workflows query GHCR / GitHub **first** and then skip or fail when the
  version is already taken. Clobbering is forbidden: no `--clobber`, no
  `git tag -f`, no re-pushing over an existing version tag.
- `latest` is pushed in the **same step** as the version tag, so the mutable
  pointer can never describe a different build than the tag beside it.
- Binary releases have **no `latest`**. `latest` is a container-registry
  concept; binaries are addressed solely by CalVer version.

### Credentials

- The correct name is **`GITHUB_PERSONAL_ACCESS_TOKEN`** everywhere:
  `$GITHUB_PERSONAL_ACCESS_TOKEN` in a shell,
  `${{ secrets.GITHUB_PERSONAL_ACCESS_TOKEN }}` in a workflow.
- It is **not a workflow secret unless it is also set as a repository or
  organisation secret of that exact name**. A shell environment variable is not
  readable as a workflow secret. If CI "cannot see the token", this is why.
- GHCR login prefers `${{ secrets.GITHUB_TOKEN }}`. It is per-run and scoped,
  and `packages: write` is granted by the workflow's own `permissions:` block,
  so it needs no configuration at all.
- Reach for the personal token only when a scope the built-in token genuinely
  lacks is required — cross-repo push, org-level settings.
- Never a literal credential in a file, a diff, a commit, a log, or an `echo`.
  A token in output is compromised: say so and rotate it.

### Git conventions

- Identity is fixed globally in `~/.gitconfig`: `PanicStack` /
  `toufr12@gmail.com`. Never commit as anyone else and never change it
  per-repo without being asked.
- Every project is under Git — `git init` before making changes.
- Default remote owner is the **`Nerqiva`** org. Never a personal account.
- Small, reviewable commits. No amend, no force-push unless explicitly asked.
- Do not create a GitHub remote, repository, or release unless explicitly asked.

### Editing conventions for this repo

- Workflows stay **parameterised**: `workflow_dispatch` inputs, with
  repository `Variables.*` as the fallback that carries the same value on push
  events. An empty input falls through to the variable, then to the documented
  default. Do not hardcode a project-specific value into a workflow here.
- `scripts/compute-calver.sh` is the **single source of truth for versioning**.
  Both workflows shell out to it so the image tag and the release version cannot
  drift. Never inline the logic into a workflow — two implementations of one
  version scheme will diverge. Any change to the version scheme is a change to
  this script *and* to the `CalVer` sections of `README.md`, in the same commit.
- Third-party actions stay pinned to a **version tag**, never `@main`:
  `actions/checkout@v7`, `actions/upload-artifact@v7`,
  `actions/download-artifact@v8`, `docker/setup-buildx-action@v4`,
  `docker/setup-qemu-action@v4`, `docker/login-action@v4`,
  `docker/metadata-action@v6`, `docker/build-push-action@v7`. Dependabot keeps
  the `docker/*` group together because a partial bump breaks the tag-generation
  contract.
- **Never type a toggle as `type: boolean`.** GitHub expressions treat `false`
  as falsy, so `inputs.x || vars.X || '<default>'` falls through and an explicit
  "off" is silently ignored — a build-only dry run becomes a real push. Toggles
  are strings (`'true'` / `'false'`) that the workflow parses and validates.
- Tag-triggered binary runs must prove the pushed tag equals the CalVer version
  of its own commit before the collision guard counts for anything.
- Workflow file and script changes are documented in the same commit that makes
  them; `README.md` describes the contract, so a contract change is a
  `README.md` change.

## Repo identity note

The repository is `Nerqiva/Reuseable-Github-Actions`. The spelling is
deliberately as-is: **do not "correct" it in URLs or image paths.** GHCR
namespace paths must be lowercase, so the image reference is written
lowercase even though the repo name is not.

## Still open

- No `LICENSE` has been chosen. The owner must pick one before this repo is
  advertised for adoption. Do not invent one.