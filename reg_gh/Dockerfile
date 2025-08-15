################# Variables ################
ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27.3
ARG OS_VERSION=bullseye-20250224-slim
ARG OS_TYPE=debian

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-${OS_TYPE}-${OS_VERSION}"
ARG RUNNER_IMAGE="${OS_TYPE}:${OS_VERSION}"
##########################################
################# BUILDER ################
##########################################
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && \
  apt-get upgrade -y --autoremove && \
  apt-get clean 

RUN apt-get install -y pkg-config openssl curl build-essential git
# prepare build dir
WORKDIR /build_space

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# set build ENV
ARG MIX_ENV=prod
ENV MIX_ENV=prod

ENV OTPROOT=/usr/lib/erlang
ENV ERL_LIBS=/usr/lib/erlang/lib

# copy reg_gh sources
COPY reg_gh/lib/ lib/
COPY reg_gh/config/ config/
COPY reg_gh/mix.exs ./

# copy ex_esdb package as local dependency
COPY package/ /build_space/ex_esdb_package

# install mix dependencies
RUN MIX_ENV="prod" mix do deps.get --only "prod", deps.compile
# build assets
RUN MIX_ENV="prod" mix do compile, release reg_gh

###################################
########### RUNTIME ###############
###################################

FROM ${RUNNER_IMAGE} AS reg_gh

ENV HOME=/system
ENV MIX_ENV="prod"
ENV PATH="${PATH}"

ARG EX_ESDB_COOKIE
ARG EX_ESDB_DATA_DIR
ARG EX_ESDB_STORE_ID
ARG EX_ESDB_CLUSTER_SECRET
ARG EX_ESDB_GOSSIP_MULTICAST_ADDR

ENV ERTS_VERSION=erts-15.2.3

RUN echo "!!!!!!!! Building reg_gh runner image...!!!!!!!!" && sleep 2

RUN apt-get update -y && \
  apt-get upgrade -y --autoremove && \
  apt-get clean && \
  apt-get install -y build-essential pkg-config openssl libncurses5 locales ca-certificates curl systemd htop procps && \
  rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /system

RUN mkdir /data

RUN chown -R nobody /data

COPY --from=builder --chown=nobody /build_space/_build/prod/rel/reg_gh/ ./

COPY reg_gh/run-reg-gh.sh .
COPY reg_gh/check-reg-gh.sh .

RUN chmod +x run-reg-gh.sh check-reg-gh.sh

ENV PATH="${PATH}:/system/${ERTS_VERSION}/bin"

VOLUME /data

EXPOSE 4369 9000-9100 45892 

RUN echo ${EX_ESDB_COOKIE} > /root/.erlang.cookie
RUN chmod 400 /root/.erlang.cookie

HEALTHCHECK --interval=10s --timeout=3s \
  CMD ["./check-reg-gh.sh"]

CMD ["./run-reg-gh.sh"]
