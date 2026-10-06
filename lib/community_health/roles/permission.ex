defmodule CommunityHealth.Roles.Permission do
  use Ecto.Schema

  schema "permissions" do
    field :code, :string
    field :name, :string

    timestamps()
  end
end
