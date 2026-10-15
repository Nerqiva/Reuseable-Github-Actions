# A minimal but REAL multi-stage image, used to prove this base repository's
# publish workflow actually works. It also demonstrates the two knobs the
# adoption checklist calls out: a build target stage, and a Debian-compatible
# runtime.
#
# Build context must be this directory:
#   docker build -f examples/hello-world/Dockerfile examples/hello-world
#
# The release workflow injects VERSION automatically as a build arg (see
# README.md, "Configuration"); the default below is only for local builds.
# syntax=docker/dockerfile:1

# --- build stage -------------------------------------------------------------
FROM golang:1.27-alpine AS build
WORKDIR /src

# Copy the module files first so the dependency layer caches independently of
# source changes. There are no third-party dependencies, so this is mostly here
# to model the habit rather than to pay off.
COPY go.mod ./
COPY main.go ./

ARG VERSION=dev
# CGO_ENABLED=0 is what makes the binary static and therefore Debian-compatible:
# no glibc version coupling, so the same artifact runs on bookworm, trixie and
# anything newer.
RUN CGO_ENABLED=0 go build \
      -trimpath \
      -ldflags "-s -w -X main.version=${VERSION}" \
      -o /out/hello-world .

# --- runtime stage -----------------------------------------------------------
# Target stage. The publish workflow's BUILD_TARGET variable selects it; the
# default final stage is the same one, so the build works either way.
FROM debian:bookworm-slim AS runtime

COPY --from=build /out/hello-world /usr/local/bin/hello-world

# Prove at build time that the artifact actually runs in the runtime image.
RUN /usr/local/bin/hello-world --name buildcheck >/dev/null

LABEL org.opencontainers.image.title="hello-world" \
      org.opencontainers.image.description="Reference fixture for Nerqiva/Reuseable-Github-Actions" \
      org.opencontainers.image.source="https://github.com/Nerqiva/Reuseable-Github-Actions"

ENTRYPOINT ["/usr/local/bin/hello-world"]
CMD ["--name", "world"]