FROM elixir:1.17-slim

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      git \
      inotify-tools \
      postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && mix local.rebar --force

WORKDIR /app

COPY mix.exs mix.lock ./
RUN mix deps.get

COPY . .

EXPOSE 4000

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["mix", "phx.server"]
