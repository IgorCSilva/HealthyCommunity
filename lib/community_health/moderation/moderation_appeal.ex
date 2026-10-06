defmodule CommunityHealth.Moderation.ModerationAppeal do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending upheld denied)

  schema "moderation_appeals" do
    field :appellant_external_id, :string
    field :reason, :string
    field :status, :string, default: "pending"
    field :reviewed_by, :string
    field :resolved_at, :utc_datetime

    belongs_to :moderation_action, CommunityHealth.Moderation.ModerationAction

    timestamps()
  end

  def changeset(appeal, attrs) do
    appeal
    |> cast(attrs, [
      :moderation_action_id,
      :appellant_external_id,
      :reason,
      :status,
      :reviewed_by,
      :resolved_at
    ])
    |> validate_required([:moderation_action_id, :appellant_external_id, :reason])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:moderation_action_id])
    |> foreign_key_constraint(:moderation_action_id)
  end

  def resolve_changeset(appeal, attrs) do
    appeal
    |> cast(attrs, [:status, :resolved_at])
    |> validate_required([:status, :resolved_at])
    |> validate_inclusion(:status, ~w(upheld denied))
  end
end
