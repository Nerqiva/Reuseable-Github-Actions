# `hello-world` — the base repo's own test fixture

A reference implementation that is never executed is documentation. This
fixture exists so the repository can **prove its own workflows work** on every
push, and so you have a runnable starting point instead of an empty box.

It is deliberately the smallest thing that still exercises the hard parts:

| What it exercises | Where |
| --- | --- |
| Multi-stage Dockerfile with an explicit target stage | `Dockerfile` (`build` → `runtime`) |
| `CGO_ENABLED=0` static build → Debian-compatible | `Dockerfile`, and the release workflow's default |
| Version baked into the artifact | `-ldflags "-X main.version=$VERSION"` |
| `BUILD_TARGET` repository Variable | selects the `runtime` stage |
| `BUILD_ARGS` `VERSION` injection | `ARG VERSION=dev` picks it up |
| `fetch-depth: 0` + `MICRO` CalVer | every push to `main` publishes a new version |
| Real binary execution on `debian:bookworm-slim` | the `verify` job in `release-binaries.yml` |

## How this repository drives its own tests

Both workflows take every build knob as a `workflow_dispatch` input, falling
back to a repository `Variable` and then to a documented default. This
repository's own test runs pass the knobs as **dispatch inputs**, so the repo
works out of the box with no configuration.

To make publishing unattended on every push to `main` — which is the point of
the `MICRO` component — set these repository Variables
(Settings → Secrets and variables → Actions → Variables). Setting them requires
repository admin; an API token without Actions write access gets a 404 here.

| Variable | Value |
| --- | --- |
| `IMAGE_NAME` | *(leave unset — defaults to `ghcr.io/nerqiva/reuseable-github-actions`)* |
| `DOCKERFILE` | `examples/hello-world/Dockerfile` |
| `BUILD_CONTEXT` | `examples/hello-world` |
| `BUILD_TARGET` | `runtime` |
| `PLATFORMS` | `linux/amd64,linux/arm64` |
| `BINARY_BUILD_COMMAND` | `cd examples/hello-world && go build -trimpath -ldflags "-s -w -X main.version=$VERSION" -o "$OUT_DIR/$BINARY_NAME" .` |
| `BINARY_NAME` | `hello-world` |
| `VERIFY_IMAGE` | `debian:bookworm-slim` |

Until they are set, a push to `main` fails the build step — there is no
`./Dockerfile` at the repository root. That is the fallback chain doing exactly
what it is documented to do, not a defect.

## Run it locally

```bash
# Container
docker build -f examples/hello-world/Dockerfile \
  --build-arg VERSION=v0.0.0-local -t hello-world:local examples/hello-world
docker run --rm hello-world:local --name local

# Binary
cd examples/hello-world
CGO_ENABLED=0 go build -trimpath -o /tmp/hello-world .
/tmp/hello-world --name local --shout
file /tmp/hello-world    # expect: statically linked
```

## Adapting it

Delete it when your project has something real. If you keep it as a smoke test,
keep it out of your own release path so it cannot collide with a real version.