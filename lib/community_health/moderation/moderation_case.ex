defmodule CommunityHealth.Moderation.ModerationCase do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending assigned decided)
  @severities ~w(low medium high critical)

  schema "moderation_cases" do
    field :reported_actor_external_id, :string
    field :severity, :string
    field :reviewer_external_id, :string
    field :status, :string, default: "pending"

    belongs_to :report, CommunityHealth.Reports.Report
    belongs_to :community, CommunityHealth.Communities.Community

    timestamps()
  end

  def changeset(moderation_case, attrs) do
    moderation_case
    |> cast(attrs, [
      :report_id,
      :community_id,
      :reported_actor_external_id,
      :severity,
      :reviewer_external_id,
      :status
    ])
    |> validate_required([:report_id, :community_id, :severity])
    |> validate_inclusion(:severity, @severities)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:report_id])
    |> foreign_key_constraint(:report_id)
    |> foreign_key_constraint(:community_id)
  end
end
