defmodule CommunityHealth.Reputation.ReputationRule do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reputation_rules" do
    field :action_type, :string
    field :points, :integer
    field :daily_cap, :integer
    field :active, :boolean, default: true

    belongs_to :community, CommunityHealth.Communities.Community

    timestamps()
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:community_id, :action_type, :points, :daily_cap, :active])
    |> validate_required([:community_id, :action_type, :points])
    |> unique_constraint([:community_id, :action_type])
    |> foreign_key_constraint(:community_id)
  end
end
