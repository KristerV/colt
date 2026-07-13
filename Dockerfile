# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?name=ubuntu
# https://hub.docker.com/_/ubuntu/tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian/tags?name=trixie-20260623-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: docker.io/hexpm/elixir:1.18.4-erlang-27.3.4.13-debian-trixie-20260623-slim
#
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4.13
ARG DEBIAN_VERSION=trixie-20260623-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

COPY assets assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

# The single scraping browser is a Node/patchright sidecar run headed under Xvfb
# (see browser/README.md). node + xvfb + xauth for it; tini to reap the browser's
# process tree; fonts + libs are patchright chromium's system deps (the rest are
# pulled by `patchright install --with-deps` below).
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       libstdc++6 openssl libncurses6 locales ca-certificates unzip curl \
       nodejs npm xvfb xauth tini fonts-liberation \
       libnss3 libxss1 libasound2 libatk-bridge2.0-0 libgtk-3-0 libgbm1 \
       dbus dbus-user-session \
  && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"
ENV COLT_BROWSER_PORT="8791"
ENV PLAYWRIGHT_BROWSERS_PATH="/app/browser/browsers"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/colt ./
RUN chmod +x /app/bin/entrypoint.sh

# Install the single stealth browser sidecar (patchright + its patched chromium).
COPY browser /app/browser
RUN cd /app/browser \
  && npm install --omit=dev --no-audit --no-fund \
  && npx patchright install --with-deps chromium \
  && chown -R nobody:root /app/browser

USER nobody

# tini reaps the Xvfb + chromium process tree the sidecar spawns.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/bin/entrypoint.sh"]
