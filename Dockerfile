# build with: docker build -t emischorr/forecaster:latest .
#  or on mac: docker buildx build --platform=linux/amd64 --no-cache -t emischorr/forecaster:latest .
# run with: docker run -d --rm -p 4000:4000 -v $PWD/data:/data -e MQTT_HOST=$MQTT_HOST -e MQTT_USER=$MQTT_USER -e MQTT_PW=$MQTT_PW -e FORECAST_PLACE=$FORECAST_PLACE emischorr/forecaster:latest start
# push with: docker push emischorr/forecaster:latest

ARG RELEASE_NAME=forecaster

ARG ELIXIR_VERSION="1.20.3"
ARG ERLANG_VERSION="28.5.0.5"
ARG ALPINE_VERSION="3.23.5"

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

# Needed for cross platform builds with newer erlang (27+). Also prevent Erlang from trying to initialize a TTY during the build
# see: https://elixirforum.com/t/mix-deps-get-memory-explosion-when-doing-cross-platform-docker-build/57157/3
ENV ERL_FLAGS="-noinput +JPperf true"

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# redeclare it as it is lost after the FROM above
ARG MIX_ENV
ARG RELEASE_NAME
ENV MIX_ENV="${MIX_ENV}"

# install mix dependencies
COPY mix.exs mix.lock ./
COPY apps/forecaster/mix.exs apps/forecaster/
COPY apps/pv_forecast/mix.exs apps/pv_forecast/
RUN mix deps.get --only $MIX_ENV

# copy compile configuration files
RUN mkdir config
COPY config/config.exs config/$MIX_ENV.exs config/

# compile dependencies
RUN mix deps.compile

# compile project
COPY apps/forecaster/lib apps/forecaster/lib
COPY apps/pv_forecast/lib apps/pv_forecast/lib
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
RUN apk add --no-cache libstdc++ openssl ncurses-libs ca-certificates

ENV USER="elixir"
# exact locale doesn't matter, but en_US gives you temperatures in fahrenheit :-(
ENV LANG=de_DE.UTF-8
# trained PV model, mount it as a volume (see docker-compose.yml)
ENV MODEL_PATH=/data/pv_forecast_ensemble.bin

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

# PV forecast HTTP API
EXPOSE 4000

ENTRYPOINT ["bin/forecaster"]

CMD ["start"]
