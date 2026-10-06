defmodule CommunityHealth.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      CommunityHealthWeb.Telemetry,
      # Start the Ecto repository
      CommunityHealth.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: CommunityHealth.PubSub},
      # Start Finch
      {Finch, name: CommunityHealth.Finch},
      # Runs the CH-Step 8 reputation rollup off the request path
      {Oban, Application.fetch_env!(:community_health, Oban)},
      # Start the Endpoint (http/https)
      CommunityHealthWeb.Endpoint
      # Start a worker by calling: CommunityHealth.Worker.start_link(arg)
      # {CommunityHealth.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CommunityHealth.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CommunityHealthWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
