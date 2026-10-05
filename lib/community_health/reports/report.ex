defmodule CommunityHealth.Reports.Report do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending reviewing resolved dismissed)

  schema "reports" do
    field :reporter_external_id, :string
    field :reason, :string
    field :description, :string
    field :status, :string, default: "pending"

    belongs_to :platform, CommunityHealth.Platforms.Platform
    belongs_to :community, CommunityHealth.Communities.Community
    belongs_to :resource, CommunityHealth.Resources.Resource

    timestamps()
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :platform_id,
      :community_id,
      :resource_id,
      :reporter_external_id,
      :reason,
      :description,
      :status
    ])
    |> validate_required([
      :platform_id,
      :community_id,
      :resource_id,
      :reporter_external_id,
      :reason
    ])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:platform_id, :resource_id, :reporter_external_id])
    |> foreign_key_constraint(:platform_id)
    |> foreign_key_constraint(:community_id)
    |> foreign_key_constraint(:resource_id)
  end
end
