#!/usr/bin/env bash
#
# Base repo: Nerqiva/Reuseable-Github-Actions
# (spelling is deliberate — see AGENTS.md; GHCR image paths are lowercase)
# See README.md for the adaptation checklist before you edit this file.
#
# Copy and adapt this file into your own repository. Never reference this repo
# from a workflow via `uses:` — see the rule in AGENTS.md.
#
# compute-calver.sh — the SINGLE SOURCE OF TRUTH for versioning.
#
# Both .github/workflows/publish-image.yml and
# .github/workflows/release-binaries.yml call this script so the image tag and the
# binary release tag can never drift apart.
#
# Derivation (do not "simplify" this):
#
#   vYYYY.MM.DD.MICRO
#     YYYY.MM.DD  = the COMMIT date in UTC, not wall-clock at run time.
#                   A re-run of the same commit MUST yield the same version.
#     MICRO       = how many commits are reachable from the ref on that same UTC
#                   day. This is the only reason "publish every commit" can coexist
#                   with "never overwrite an existing version": each commit of the
#                   day gets a distinct MICRO. Do NOT drop it and do NOT replace it
#                   with a job counter or run number.
#
# INVARIANT: `latest` is the ONLY tag that may ever be overwritten, and it is a
# GHCR-image concept only. CalVer tags and releases are immutable. This script
# enforces that with a pre-write collision guard (tag + release existence).
#
# Usage:
#   scripts/compute-calver.sh [<ref>]      # default ref: HEAD
#
# Outputs (to $GITHUB_OUTPUT when running inside Actions, to stdout otherwise):
#   version=v2026.10.14.3
#   day=2026.10.14
#   micro=3
#   commit_date=2026-10-14T09:12:33+00:00
#
# Environment:
#   GITHUB_TOKEN              token used ONLY for the release existence check,
#                             sent as an Authorization header. Never printed.
#   GITHUB_REPOSITORY         owner/repo for that check. If unset, the release
#                             check is SKIPPED with a warning (not a crash).
#   GITHUB_API_URL            defaults to https://api.github.com
#   ALLOW_EXISTING_VERSION    "true" turns a collision into a warning instead of an
#                             error. DEFAULT false. This is a deliberate recovery
#                             hatch for a half-finished publish (image pushed, release
#                             step failed). Never set it to paper over a real conflict.
#   ALLOW_EXISTING_TAG       "true" is for tag-triggered workflows only: the run was
#                             started BY refs/tags/$VERSION, so the tag is expected to
#                             exist and must never be re-created or moved. It does NOT
#                             relax the release check. The caller must not pass -f / --force.
set -euo pipefail

REF="${1:-HEAD}"

# Emit to the Actions output file when present, otherwise to stdout so the script
# is runnable and testable on a laptop.
GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"
ALLOW_EXISTING_VERSION="${ALLOW_EXISTING_VERSION:-false}"
ALLOW_EXISTING_TAG="${ALLOW_EXISTING_TAG:-false}"
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"

err() { printf '%s\n' "$*" >&2; }
note() { printf '::notice::%s\n' "$*" >&2; }
warn() { printf '::warning::%s\n' "$*" >&2; }
fail() { printf '::error::%s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preconditions
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  fail "compute-calver.sh must run inside a git repository (no .git found from $(pwd)). Check out the repo before calling it."
fi

# Resolve the ref to a commit object first. This keeps the derivation below
# unambiguous when the ref looks like a path, and fails loudly on a bad ref.
COMMIT_SHA="$(git rev-parse --verify "${REF}^{commit}" 2>/dev/null)" \
  || fail "Ref '${REF}' does not resolve to a commit."

# MICRO counts commits by *committer* date, so a shallow clone silently yields a
# wrong (too small) number rather than an obvious error. Refuse to guess.
if [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo false)" = "true" ]; then
  fail "Repository is a shallow clone, so MICRO cannot be counted correctly. Check out with 'fetch-depth: 0' before calling compute-calver.sh."
fi

# ------------------------------------------------------------------- derivation
COMMIT_DATE="$(git show -s --format=%cI "$COMMIT_SHA")"
DAY="$(date -u -d "$COMMIT_DATE" +%Y.%m.%d)"
MICRO="$(git rev-list --count --since="${DAY} 00:00:00 UTC" --until="${DAY} 23:59:59 UTC" "$COMMIT_SHA")"
MICRO="$(printf '%s' "$MICRO" | tr -d '[:space:]')"

if [ -z "$MICRO" ] || [ "$MICRO" -le 0 ]; then
  fail "Computed MICRO='${MICRO}' for ${DAY}, which is not sane. This almost always means the checkout history is too shallow — use 'fetch-depth: 0' — or that the ref's commit date falls outside the queried UTC day."
fi

VERSION="v${DAY}.${MICRO}"

# -------------------------------------------------------------- collision guard
# Callers MUST NOT write a tag or a release until this guard has passed.
TAG_TAKEN=false
TAG_LOOKUP_OK=true
RELEASE_TAKEN=false

# git ls-remote --exit-code: 0 = found, 2 = no matching ref, anything else = the
# remote could not be consulted. A failed lookup must not be reported as "free":
# warn loudly instead. It does not fail the run on purpose — a transient DNS
# failure should not block every publish, and there are defence layers behind
# this guard anyway (git refuses to push over an existing tag without --force,
# and `gh release create` is run without --clobber).
set +e
git ls-remote --exit-code --tags origin "refs/tags/${VERSION}" >/dev/null 2>&1
ls_remote_rc=$?
set -e
case "$ls_remote_rc" in
  0) TAG_TAKEN=true ;;
  2) : ;;
  *)
    TAG_LOOKUP_OK=false
    warn "Could not query origin for refs/tags/${VERSION} (git ls-remote exited ${ls_remote_rc}, e.g. no remote configured or the host is unreachable). Treating the tag as unverified; the push itself will still be rejected by the remote if ${VERSION} already exists."
    ;;
esac

if [ -n "${GITHUB_REPOSITORY:-}" ]; then
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    # No token: we simply cannot check. Skip loudly rather than pretending.
    warn "GITHUB_TOKEN is unset, skipping the release existence check for ${GITHUB_REPOSITORY}."
  else
    body_file="$(mktemp)"
    err_file="$(mktemp)"
    trap 'rm -f "$body_file" "$err_file"' EXIT
    # The token is passed via a header and is never echoed, traced or logged.
    if http_code="$(curl --silent --show-error --location \
      --output "$body_file" \
      --write-out '%{http_code}' \
      --header "Authorization: Bearer ${GITHUB_TOKEN}" \
      --header "Accept: application/vnd.github+json" \
      --header "X-GitHub-Api-Version: 2022-11-28" \
      "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/releases/tags/${VERSION}" 2>"$err_file")"; then
      case "$http_code" in
        200) RELEASE_TAKEN=true ;;
        404) : ;; # no release for this tag — this is the happy path
        401 | 403)
          fail "GitHub API returned ${http_code} while checking whether release ${VERSION} exists. Failing closed because an unverifiable release must be treated as a conflict."
          ;;
        *)
          warn "GitHub API returned ${http_code} while checking release ${VERSION}; skipping that check. Re-run the job if this was a transient error."
          ;;
      esac
    else
      warn "Could not reach ${GITHUB_API_URL} to check release ${VERSION}: $(tr -d '\n' <"$err_file"). Skipping that check."
    fi
  fi
else
  warn "GITHUB_REPOSITORY is unset, skipping the release existence check for ${VERSION}."
fi

if [ "$TAG_TAKEN" = true ] && [ "${ALLOW_EXISTING_TAG}" != "true" ]; then
  # The tag already exists on the remote: this is a re-run of an already published
  # commit. Overwriting is FORBIDDEN. There is deliberately no --force, no --clobber
  # and no 'git tag -f' anywhere in this repo.
  if [ "${ALLOW_EXISTING_VERSION}" = "true" ]; then
    warn "Tag ${VERSION} already exists on the remote. ALLOW_EXISTING_VERSION=true, so this is downgraded to a warning. Do not move or overwrite the existing tag."
  else
    fail "Tag ${VERSION} already exists on the remote. Refusing to overwrite it. Re-running a publish for an already-published commit is expected to fail here; 'latest' is the only mutable tag and it is not affected."
  fi
elif [ "$TAG_TAKEN" = true ]; then
  note "Tag ${VERSION} exists on the remote, as expected for a tag-triggered run. It will not be re-created or moved."
elif [ "$TAG_TAKEN" = false ] && [ "$TAG_LOOKUP_OK" = true ]; then
  if [ "${ALLOW_EXISTING_TAG}" = "true" ]; then
    fail "ALLOW_EXISTING_TAG=true but tag ${VERSION} does not exist on the remote. This run was supposed to be triggered by that tag; the tag is missing."
  fi
fi

if [ "$RELEASE_TAKEN" = true ]; then
  if [ "${ALLOW_EXISTING_VERSION}" = "true" ]; then
    warn "Release ${VERSION} already exists. ALLOW_EXISTING_VERSION=true, so this is downgraded to a warning. Finish the half-finished publish or pick a new version."
  else
    fail "Release ${VERSION} already exists for ${GITHUB_REPOSITORY:-the current repository}. Refusing to overwrite it. Release 'gh release create' is intentionally run without --clobber."
  fi
fi

# ---------------------------------------------------------------------- output
payload="$(
  printf 'version=%s\n' "$VERSION"
  printf 'day=%s\n' "$DAY"
  printf 'micro=%s\n' "$MICRO"
  printf 'commit_date=%s\n' "$COMMIT_DATE"
)"

# Inside Actions: append to the output file so the caller can read
# steps.<id>.outputs.<key>. Outside Actions (local testing): plain stdout.
if [ -n "$GITHUB_OUTPUT" ]; then
  printf '%s\n' "$payload" >>"$GITHUB_OUTPUT"
else
  printf '%s\n' "$payload"
fi

# Always show the version in the log, in both output modes.
err "CalVer for ${REF} (${COMMIT_SHA}): ${VERSION} (day=${DAY}, micro=${MICRO}, commit_date=${COMMIT_DATE})"
