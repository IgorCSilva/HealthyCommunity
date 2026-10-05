defmodule CommunityHealth.Actions.CommunityAction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "community_actions" do
    field :actor_external_id, :string
    field :action_type, :string
    field :event_key, :string
    field :context, :map, default: %{}
    field :occurred_at, :utc_datetime

    belongs_to :platform, CommunityHealth.Platforms.Platform
    belongs_to :community, CommunityHealth.Communities.Community
    belongs_to :resource, CommunityHealth.Resources.Resource

    timestamps(updated_at: false)
  end

  def changeset(action, attrs) do
    action
    |> cast(attrs, [
      :platform_id,
      :community_id,
      :resource_id,
      :actor_external_id,
      :action_type,
      :event_key,
      :context,
      :occurred_at
    ])
    |> validate_required([
      :platform_id,
      :community_id,
      :resource_id,
      :actor_external_id,
      :action_type,
      :event_key,
      :occurred_at
    ])
    |> unique_constraint([:platform_id, :event_key])
    |> foreign_key_constraint(:platform_id)
    |> foreign_key_constraint(:community_id)
    |> foreign_key_constraint(:resource_id)
  end
end
