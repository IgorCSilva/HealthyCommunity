defmodule CommunityHealth.Communities.Community do
  use Ecto.Schema
  import Ecto.Changeset

  schema "communities" do
    field :external_ref, :string
    field :name, :string
    belongs_to :platform, CommunityHealth.Platforms.Platform

    timestamps()
  end

  def changeset(community, attrs) do
    community
    |> cast(attrs, [:external_ref, :name, :platform_id])
    |> validate_required([:external_ref, :name, :platform_id])
    |> unique_constraint([:platform_id, :external_ref])
    |> foreign_key_constraint(:platform_id)
  end
end
