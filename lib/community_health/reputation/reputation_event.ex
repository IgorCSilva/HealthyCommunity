defmodule CommunityHealth.Reputation.ReputationEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reputation_events" do
    field :actor_external_id, :string
    field :action_type, :string
    field :points, :integer
    field :occurred_at, :utc_datetime

    belongs_to :community, CommunityHealth.Communities.Community
    belongs_to :community_action, CommunityHealth.Actions.CommunityAction

    timestamps(updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :community_id,
      :actor_external_id,
      :action_type,
      :points,
      :community_action_id,
      :occurred_at
    ])
    |> validate_required([
      :community_id,
      :actor_external_id,
      :action_type,
      :points,
      :community_action_id,
      :occurred_at
    ])
    |> unique_constraint([:community_action_id])
    |> foreign_key_constraint(:community_id)
    |> foreign_key_constraint(:community_action_id)
  end
end
