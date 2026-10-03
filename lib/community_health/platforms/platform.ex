defmodule CommunityHealth.Platforms.Platform do
  use Ecto.Schema
  import Ecto.Changeset

  schema "platforms" do
    field :name, :string
    field :code, :string

    timestamps()
  end

  def changeset(platform, attrs) do
    platform
    |> cast(attrs, [:name, :code])
    |> validate_required([:name, :code])
    |> unique_constraint(:code)
  end
end
