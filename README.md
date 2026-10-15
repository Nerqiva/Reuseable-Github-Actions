# Reusable GitHub Actions

A reference implementation of the two GitHub Actions workflows most projects end
up writing by hand: **publish a Docker image to GHCR**, and **cut a binary
release** for Linux `amd64` and `arm64`. It ships the workflows, a version scheme
that survives "publish on every commit", and the guardrails that stop a re-run
from silently replacing a published artefact.

> **Rule — copy and adapt, never `uses:`.**
> Take the files into your own repository and edit them there. Do **not** point
> your workflow at this repo with
> `uses: Nerqiva/Reuseable-Github-Actions/.github/workflows/...@main`. A `uses:`
> reference ties your release cadence to commits made here: a rename or a
> refactor upstream breaks your release, and you inherit failures from a change
> you never reviewed. Copy the file, then own it.

Repository: [`Nerqiva/Reuseable-Github-Actions`](https://github.com/Nerqiva/Reuseable-Github-Actions)
— the spelling is deliberate and must not be "corrected" in image paths. GHCR
namespace paths are lowercase regardless:
`ghcr.io/nerqiva/reuseable-github-actions`.

## What you get

| Workflow | What it does | When it runs | What it produces |
| --- | --- | --- | --- |
| `.github/workflows/publish-image.yml` | Builds the Docker image and pushes it to GHCR. | `workflow_dispatch`, **and** push to the default branch `main`. | An immutable CalVer tag (`v2026.10.14.3`) and the mutable `latest`, pushed in the **same step**. |
| `.github/workflows/release-binaries.yml` | Builds Debian-compatible Linux binaries and attaches them to a GitHub Release. | `push` on `v*` tags, **and** `workflow_dispatch`. | Release assets `<name>-<version>-linux-<arch>.tar.gz`. **No `latest`.** |

`release-binaries.yml` verifies each binary actually executes inside
`debian:bookworm-slim` before the release is created, so a broken cross-compile
fails loudly instead of shipping.

> **Rule — immutability.**
> `latest` is **mutable**, **GHCR-only**, and is the **only** tag that may be
> overwritten. CalVer version tags and GitHub Releases are **immutable** and are
> **never** replaced: both workflows check GHCR / GitHub first and then skip or
> fail rather than clobber. `--clobber` and `git tag -f` are forbidden.

## Required secrets

| Secret | Where it comes from | When you need it |
| --- | --- | --- |
| `GITHUB_TOKEN` | Automatic. GitHub mints it per run; **no configuration at all.** | Always, for the GHCR path. `packages: write` is granted by the workflow's own `permissions:` block. |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | Your account → Settings → Developer settings → Personal access tokens. Add it as a repository or organisation secret of that exact name. | Only if a scope the built-in token genuinely lacks is required — cross-repo push, org-level settings. `packages: write` at minimum. |

**None of these are ever typed into a file.** Credentials belong in repository
or organisation secrets only, and reach the workflow as `${{ secrets.NAME }}`.
A personal token that lives only in your shell as `$GITHUB_PERSONAL_ACCESS_TOKEN`
is *not* readable as a workflow secret — if CI cannot see it, it was never
registered as one.

## Quick start

```bash
# 1. Copy the workflow(s) you want into your repo, AND the version script.
#    The script is NOT optional — both workflows shell out to it, and a run
#    without it fails in the version job before anything is built or pushed.
mkdir -p .github/workflows scripts
cp /path/to/this/repo/.github/workflows/publish-image.yml    .github/workflows/
cp /path/to/this/repo/.github/workflows/release-binaries.yml .github/workflows/
cp /path/to/this/repo/scripts/compute-calver.sh              scripts/
chmod +x scripts/compute-calver.sh
```

> **Copy `scripts/compute-calver.sh` together with any workflow that uses it.**
> It is the single source of truth for versioning, so the image tag and the
> release version cannot drift apart. If you inline the logic into the workflow
> instead, you now own keeping the two copies in sync — that is the one place
> where drift silently ships a version that disagrees with itself.

```bash
# 2. Set the repository Variables (Settings → Secrets and variables → Actions)
#    These are what the workflows fall back to on push events, where no
#    workflow_dispatch input exists. Requires repo admin.
#    IMAGE_NAME=ghcr.io/your-org/your-repo      (lowercase only)
#    DOCKERFILE=./Dockerfile
#    BUILD_CONTEXT=.
#    PLATFORMS=linux/amd64,linux/arm64
#    # and, if you copy release-binaries.yml (both are required, no default):
#    BINARY_BUILD_COMMAND='go build -o "$OUT_DIR/$BINARY_NAME" ./cmd/yourapp'
#    BINARY_NAME=yourapp

# 3. Secret: usually nothing to do. GITHUB_TOKEN is automatic.
#    Only if you truly need more scope:
#    Settings → Secrets and variables → Actions → New repository secret
#      name: GITHUB_PERSONAL_ACCESS_TOKEN

# 4. Repo must allow Actions to write packages:
#    Settings → Actions → General → Workflow permissions → Read and write

# 5. Enable and run it
#    Actions → publish-image → Run workflow
```

## Configuration

Values resolve in this order: **`workflow_dispatch` input → repository
`Variables.*` → documented default**. An empty input falls through to the
variable; a missing or empty variable falls through to the default. On `push`
events there are no inputs at all, which is exactly why the variables exist —
without them the workflow only works when you click Run.

If you adapt a file, confirm the names in your copy:

```bash
grep -n -A60 'workflow_dispatch' .github/workflows/publish-image.yml
```

### `publish-image.yml`

| Input | Variable | Type | Default | Meaning |
| --- | --- | --- | --- | --- |
| `image_name` | `IMAGE_NAME` | string | `ghcr.io/<owner>/<repo>` lowercased | Full image reference. **Lowercase only** — GHCR rejects uppercase. |
| `dockerfile` | `DOCKERFILE` | string | `./Dockerfile` | Dockerfile to build, relative to the checkout. |
| `context` | `BUILD_CONTEXT` | string | `.` | Build context directory. |
| `target` | `BUILD_TARGET` | string | *(empty)* | Build stage of a multi-stage Dockerfile; empty means the Dockerfile default stage. |
| `platforms` | `PLATFORMS` | comma list | `linux/amd64,linux/arm64` | Platforms to build. Every listed platform must actually compile. |
| `build_args` | `BUILD_ARGS` | newline list | *(empty)* | `KEY=value` build args. Malformed entries fail the run rather than passing an empty `ARG`. `VERSION` is injected automatically — see below. |
| `push` | `PUSH` | string `true`\|`false` | `true` | Set `'false'` for a build-only dry run. **A string, not a boolean** — see the note below. |
| `tags` | `EXTRA_TAGS` | newline list | *(empty)* | Extra tags, applied **in addition to** the CalVer tag and `latest`. |
| `allow_existing_version` | `ALLOW_EXISTING_VERSION` | string `true`\|`false` | `false` | **Recovery hatch only.** Downgrades a version collision to a warning. Leave it off. |

Also read, for image labels only: `IMAGE_LICENSE` (defaults to `unknown`).

> **`VERSION` is injected into `build-args` automatically.** The resolved CalVer
> version is appended as `VERSION=vYYYY.MM.DD.MICRO` so a Dockerfile can
> `ARG VERSION` and bake in its own version instead of shipping `dev` under a
> version tag. An explicit `VERSION=` in `BUILD_ARGS` wins — the workflow never
> overrides a value you set yourself. Declare `ARG VERSION=dev` in the Dockerfile
> so a plain local `docker build` still works.

### `release-binaries.yml`

| Input | Variable | Type | Default | Meaning |
| --- | --- | --- | --- | --- |
| `build_command` | `BINARY_BUILD_COMMAND` | string | *(empty)* | **Required.** Shell command that produces the binary. Runs with `$VERSION`, `$OUT_DIR`, `$GOOS`, `$GOARCH`, `$CGO_ENABLED` available. |
| `binary_name` | `BINARY_NAME` | string | *(empty)* | **Required.** Executable produced in `$OUT_DIR`; stems the asset name. |
| `cgo_enabled` | `CGO_ENABLED` | string | `0` | `0` keeps the output static and Debian-compatible. |
| `strip_binary` | `STRIP_BINARY` | string `true`\|`false` | `true` | Strip before packaging. |
| `verify_image` | `VERIFY_IMAGE` | string | `debian:bookworm-slim` | Container used to prove the binary actually runs. |
| `verify_args` | `VERIFY_ARGS` | string | `--version` | Argument the verify job passes to the binary. **Contract: the binary must accept it and exit 0.** Point it at whatever your CLI accepts, or set it empty to run with no arguments. |
| `prerelease` | `PRERELEASE` | string `true`\|`false` | `false` | Mark the release as a pre-release. A pre-release is still immutable — promoting one to a full release later is a deliberate act on the same version, never a re-publish under a new one. |
| `allow_existing_version` | `ALLOW_EXISTING_VERSION` | string `true`\|`false` | `false` | **Recovery hatch only.** Leave it off. |

Architectures are a build matrix in the workflow (`linux/amd64`, `linux/arm64`),
not an input — extend the matrix, do not add a platform input. Tag-triggered
runs take the pushed `v*` tag verbatim; dispatch-triggered runs call the same
CalVer script the image workflow uses, so the two can never disagree.

> **Note on `allow_existing_version`**
> It is the one knob that weakens the immutability rule, and it exists for
> recovering from a half-finished publish. Every other path is a hard failure.
> If you find yourself setting it, the real fix is usually the version script.

> **Why `push` and `allow_existing_version` are strings, not `type: boolean`**
> GitHub expressions treat `false` as falsy. A boolean input makes
> `inputs.push || vars.PUSH || 'true'` fall through to the default — so a user
> who selects a build-only dry run would get a **real push**, silently. The
> string `'false'` is truthy, survives the fallback chain, and is parsed and
> validated explicitly in the workflow. Keep them strings if you re-type them.

## The adaptation checklist

| Base repo assumes | Your project probably differs | Where to change it |
| --- | --- | --- |
| `ghcr.io/nerqiva/reuseable-github-actions` | `ghcr.io/<your-org>/<your-repo>` — **lowercase only** | `IMAGE_NAME` variable and the `docker/metadata-action` `images:` input |
| Builds a Dockerfile | May be a bare build command, a Makefile, or a Go/Rust module | `DOCKERFILE` variable, `BUILD_CONTEXT`, or `BINARY_BUILD_COMMAND` |
| `./Dockerfile` | `docker/Dockerfile`, `deploy/Dockerfile`, … | `DOCKERFILE` variable |
| Context `.` | A subdirectory | `BUILD_CONTEXT` variable |
| Single final stage | Multi-stage with an explicit runtime target | `BUILD_TARGET` variable, or `BUILD_ARGS` |
| `linux/amd64,linux/arm64` | Whatever you actually build | `PLATFORMS` variable for the image; the `matrix:` block in `release-binaries.yml` for binaries. **A platform that cannot compile fails the whole push — including `latest`.** |
| Debian-compatible, static binaries, verified on `debian:bookworm-slim` | Alpine or musl, or a runtime with shared-library assumptions | `VERIFY_IMAGE`, `CGO_ENABLED`, and any `ldd` assumptions in the verify step |
| Ships binaries from a `build_command` | Cargo, `go build`, `make`, or a Zig/`CMAKE` build | `BINARY_BUILD_COMMAND` — it must write the executable to `$OUT_DIR`/`$BINARY_NAME` |
| Ships binaries | Is a library, a service-only image, or a web app with no CLI | Delete `release-binaries.yml` entirely. Do not keep a workflow you do not use. |
| `main` pushes publish; `v*` tags release | Release only on tags, or publish on a release branch | The `on:` block of each workflow |
| `packages: write` via `GITHUB_TOKEN` | Cross-repo push or org settings needed | Add `GITHUB_PERSONAL_ACCESS_TOKEN` as a secret and widen `permissions:` |
| CalVer `vYYYY.MM.DD.MICRO` | SemVer, or an existing scheme | The version step — read "If the target repo already has CI" below first |
| Weekly Dependabot, `docker/*` grouped | Monthly, or not at all | `.github/dependabot.yml` |

## What to keep verbatim

These lines carry the correctness guarantees. They are also the lines a hasty
editor deletes, because they look like ceremony rather than like the build.

| Keep | If you delete it |
| --- | --- |
| CalVer computed from **commit date in UTC** with a **`MICRO`** counter | Re-running a workflow mints a new version for the same commit, and the same-day second commit collides with the first and fails. |
| `fetch-depth: 0` on `actions/checkout` in the version job | A shallow clone silently returns a **smaller, wrong** `MICRO`. The version looks fine and is wrong. |
| `scripts/compute-calver.sh`, shared by both workflows | Copy one workflow without it and the version job fails before anything is built or pushed. Maintain two copies instead and the image tag and the release version drift apart. |
| The collision check against GHCR / GitHub | An existing immutable version is overwritten. Anyone who pinned that version silently gets different bytes. |
| `latest` pushed in the **same step** as the version tag | `latest` can drift onto a different build than the tag next to it. A stale `latest` is the classic symptom. |
| Credentials from `secrets.*` only | A token lands in a file, a diff, or a log. It is compromised the moment it is printed. |
| Third-party actions pinned to a version tag, never `@main` | An upstream breaking change lands in your release with no commit of yours. Currently `actions/checkout@v7`, `actions/upload-artifact@v7`, `actions/download-artifact@v8`, `docker/setup-buildx-action@v4`, `docker/setup-qemu-action@v4`, `docker/login-action@v4`, `docker/metadata-action@v6`, `docker/build-push-action@v7`. |

## If the target repo already has CI

The target repo's conventions win. This base repo is a starting point, not a
standard to impose.

- **Version scheme** — keep the existing one unless it is semver *and* migration
  was explicitly requested. Replacing a scheme nobody asked for breaks every
  consumer of your tags at once.
- **Secret names** — keep existing names. Renaming one breaks every other
  workflow in the repo that reads it, including ones you have never seen.
- **Pinning style** — if the repo pins to SHAs, stay on SHAs. Consistency beats
  preference here.
- **Release cadence** — if releases are gated on annotated tags, keep that gate.
  Publishing on every push is a policy choice, not a best practice.

Adopt the pieces that fill a gap you actually have.

## Adopting this in your repo

Add a line to your `README.md` or `AGENTS.md`:

> CI/CD adapted from `Nerqiva/Reuseable-Github-Actions` (copy-and-adapt; CalVer
> `vYYYY.MM.DD.MICRO`). Adapted: image name, Dockerfile path, release trigger on
> `v*` tags only.

Say **which parts were adapted**, not just where it came from. Six months later
that line is the only thing separating a deliberate choice from a leftover that
nobody dares to touch.

## Versioning reference

CalVer, format **`vYYYY.MM.DD.MICRO`** — for example `v2026.10.14.3`.

| Component | Source | Why |
| --- | --- | --- |
| `YYYY.MM.DD` | The **commit date in UTC** | Not the run-time wall clock. A re-run of the same commit yields the same version, so a failed publish can be retried safely. |
| `MICRO` | Number of commits on that UTC day | Makes every commit on a day unique, so "publish every commit" coexists with "never overwrite an immutable tag". |

### Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Second publish on the same UTC day fails as "version already exists" | `MICRO` was dropped, so both commits produced the same version. | Restore the per-day commit counter. |
| The version changes when you re-run the same commit | The date came from run time instead of commit time. | Derive `YYYY.MM.DD` from the commit date in UTC. |
| CI cannot see the token | `GITHUB_PERSONAL_ACCESS_TOKEN` was set as a shell env var only. A shell variable is not a workflow secret. | Add it as a repository or organisation secret of the same name. |
| `latest` is stale | It was not pushed in the same step as the version tag, or an earlier step failed. | Push version tag and `latest` together; check which step failed. |
| GHCR rejects the image path | Uppercase characters in the namespace. | Lowercase the entire `ghcr.io/<owner>/<repo>` path. |
| The whole push fails, `latest` included | One entry in `PLATFORMS` cannot compile. | Remove the platform or fix the build; there is no partial push. |

## License

[MIT](LICENSE) — free to use, including commercially. Copy these workflows into
a proprietary project without restriction; keep the copyright notice and the
permission notice with any substantial copy you redistribute.

That is deliberate: the point of this repository is that you take the files and
own them, so the license has to permit exactly that.

Contributions are welcome in the form of a better default, not a
project-specific special case: the value of this repo is that a copied workflow
is correct on the first try.