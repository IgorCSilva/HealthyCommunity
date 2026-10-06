defmodule CommunityHealth.Roles.Role do
  use Ecto.Schema

  schema "roles" do
    field :code, :string
    field :name, :string

    timestamps()
  end
end
