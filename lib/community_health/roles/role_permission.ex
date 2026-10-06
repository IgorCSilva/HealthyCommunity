defmodule CommunityHealth.Roles.RolePermission do
  use Ecto.Schema

  schema "role_permissions" do
    belongs_to :role, CommunityHealth.Roles.Role
    belongs_to :permission, CommunityHealth.Roles.Permission

    timestamps()
  end
end
