# build with: docker build -t emischorr/forecaster:latest .
# run with: docker run -d --rm -e MQTT_HOST=$MQTT_HOST -e MQTT_USER=$MQTT_USER -e MQTT_PW=$MQTT_PW -e SELENIUM_HOST=$SELENIUM_HOST -e FORECAST_PLACE=$FORECAST_PLACE emischorr/forecaster:latest start
# push with: docker push emischorr/forecaster:latest

ARG RELEASE_NAME=forecaster

ARG ELIXIR_VERSION="1.16.3"
ARG ERLANG_VERSION="26.2.5"
ARG ALPINE_VERSION="3.18.6"

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-alpine-${ALPINE_VERSION}"
ARG RUNNER_IMAGE="alpine:${ALPINE_VERSION}"

# -----------------------------------------------------------------------------
ARG MIX_ENV="prod"

# build stage
FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apk add --no-cache build-base git python3 curl

# sets work dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# redeclare it as it is lost after the FROM above
ARG MIX_ENV
ENV MIX_ENV="${MIX_ENV}"
# needed for cross platform builds with new erlang.
# see: https://elixirforum.com/t/mix-deps-get-memory-explosion-when-doing-cross-platform-docker-build/57157/3
ENV ERL_FLAGS="+JPperf true"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

# copy compile configuration files
RUN mkdir config
COPY config/config.exs config/$MIX_ENV.exs config/

# compile dependencies
RUN mix deps.compile

# copy assets
#COPY priv priv
#COPY assets assets

# Compile assets
#RUN mix assets.deploy

# compile project
COPY lib lib
RUN mix compile

# copy runtime configuration file
COPY config/runtime.exs config/

# assemble release
RUN mix release $RELEASE_NAME


# -----------------------------------------------------------------------------

# app stage
FROM ${RUNNER_IMAGE} AS runner

ARG RELEASE_NAME
ARG MIX_ENV

# install runtime dependencies
RUN apk add --no-cache libstdc++ openssl ncurses-libs

ENV USER="elixir"
ENV LANG de_DE.UTF-8

WORKDIR "/home/${USER}/app"

# Create  unprivileged user to run the release
RUN \
  addgroup \
  -g 1000 \
  -S "${USER}" \
  && adduser \
  -s /bin/sh \
  -u 1000 \
  -G "${USER}" \
  -h "/home/${USER}" \
  -D "${USER}" \
  && su "${USER}"

# run as user
USER "${USER}"

# copy release executables
COPY --from=builder --chown="${USER}":"${USER}" /app/_build/"${MIX_ENV}"/rel/"${RELEASE_NAME}" ./

ENTRYPOINT ["bin/forecaster"]

CMD ["start"]
