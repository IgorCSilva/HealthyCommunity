defmodule CommunityHealth.Platforms.ApiKey do
  use Ecto.Schema
  import Ecto.Changeset

  schema "api_keys" do
    field :token_hash, :string
    field :revoked_at, :utc_datetime
    belongs_to :platform, CommunityHealth.Platforms.Platform

    timestamps()
  end

  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:token_hash, :platform_id, :revoked_at])
    |> validate_required([:token_hash, :platform_id])
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:platform_id)
  end
end
