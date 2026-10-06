# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :community_health,
  ecto_repos: [CommunityHealth.Repo]

# Configures the endpoint
config :community_health, CommunityHealthWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [json: CommunityHealthWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CommunityHealth.PubSub

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# CH-Step 8's reputation rollup runs as an Oban job off the request path,
# same reasoning as Underlined's own Oban usage (api/config/config.exs) —
# recomputing an actor's score never blocks the ingestion request that
# triggered it.
config :community_health, Oban,
  repo: CommunityHealth.Repo,
  queues: [reputation: 5, moderation: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: :timer.hours(24 * 7)},
    Oban.Plugins.Lifeline
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
