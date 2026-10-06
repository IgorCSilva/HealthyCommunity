defmodule CommunityHealth.Reputation.ReputationScore do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reputation_scores" do
    field :actor_external_id, :string
    field :score, :integer, default: 0

    belongs_to :community, CommunityHealth.Communities.Community

    timestamps()
  end

  def changeset(score, attrs) do
    score
    |> cast(attrs, [:community_id, :actor_external_id, :score])
    |> validate_required([:community_id, :actor_external_id, :score])
    |> unique_constraint([:community_id, :actor_external_id])
    |> foreign_key_constraint(:community_id)
  end
end
