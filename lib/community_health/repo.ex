defmodule CommunityHealth.Repo do
  use Ecto.Repo,
    otp_app: :community_health,
    adapter: Ecto.Adapters.Postgres
end
