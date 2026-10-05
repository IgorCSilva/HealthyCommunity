defmodule CommunityHealth.Rules.CommunityRule do
  use Ecto.Schema
  import Ecto.Changeset

  @severities ~w(low medium high critical)

  schema "community_rules" do
    field :code, :string
    field :name, :string
    field :description, :string
    field :severity, :string
    field :active, :boolean, default: true

    belongs_to :community, CommunityHealth.Communities.Community

    timestamps()
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:community_id, :code, :name, :description, :severity, :active])
    |> validate_required([:community_id, :code, :name, :severity])
    |> validate_inclusion(:severity, @severities)
    |> unique_constraint([:community_id, :code])
    |> foreign_key_constraint(:community_id)
  end
end
