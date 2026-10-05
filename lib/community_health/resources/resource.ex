defmodule CommunityHealth.Resources.Resource do
  use Ecto.Schema
  import Ecto.Changeset

  schema "resources" do
    field :resource_type, :string
    field :external_ref, :string
    belongs_to :platform, CommunityHealth.Platforms.Platform

    timestamps()
  end

  def changeset(resource, attrs) do
    resource
    |> cast(attrs, [:platform_id, :resource_type, :external_ref])
    |> validate_required([:platform_id, :resource_type, :external_ref])
    |> unique_constraint([:platform_id, :resource_type, :external_ref])
    |> foreign_key_constraint(:platform_id)
  end
end
