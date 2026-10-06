defmodule CommunityHealth.Communities.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  schema "community_members" do
    field :actor_external_id, :string
    belongs_to :community, CommunityHealth.Communities.Community
    belongs_to :role, CommunityHealth.Roles.Role

    timestamps()
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:actor_external_id, :community_id, :role_id])
    |> validate_required([:actor_external_id, :community_id])
    |> unique_constraint([:community_id, :actor_external_id])
    |> foreign_key_constraint(:community_id)
    |> foreign_key_constraint(:role_id)
  end
end
