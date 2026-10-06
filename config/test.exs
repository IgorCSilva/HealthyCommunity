import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :community_health, CommunityHealth.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "community_health_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Lets `docker compose exec -e MIX_ENV=test app mix test` point at the
# compose postgres service instead of localhost, same as config/dev.exs.
# Deliberately TEST_DATABASE_URL, not DATABASE_URL — the app service's
# DATABASE_URL is hardcoded to community_health_dev, so honoring it here
# would make "test" runs silently read/write the dev database.
if test_database_url = System.get_env("TEST_DATABASE_URL") do
  config :community_health, CommunityHealth.Repo, url: test_database_url
end

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :community_health, CommunityHealthWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "zbh6jS6+WpUm4a0fzvB0HFhaPflylrsRjsZP6gp9qyAAyofIIyWzSng5MVwoIqhs",
  server: false

# Reputation-rollup jobs are enqueued with Oban.Testing instead of waiting
# for a runner, same as Underlined's config/test.exs.
config :community_health, Oban, testing: :manual, queues: false, plugins: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
