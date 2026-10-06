defmodule CommunityHealth.Moderation.ModerationDecision do
  use Ecto.Schema
  import Ecto.Changeset

  @decisions ~w(violation no_violation unclear)

  schema "moderation_decisions" do
    field :reviewer_external_id, :string
    field :decision, :string
    field :notes, :string

    belongs_to :moderation_case, CommunityHealth.Moderation.ModerationCase
    belongs_to :rule, CommunityHealth.Rules.CommunityRule

    timestamps(updated_at: false)
  end

  def changeset(decision, attrs) do
    decision
    |> cast(attrs, [:moderation_case_id, :reviewer_external_id, :decision, :rule_id, :notes])
    |> validate_required([:moderation_case_id, :reviewer_external_id, :decision])
    |> validate_inclusion(:decision, @decisions)
    |> unique_constraint([:moderation_case_id])
    |> foreign_key_constraint(:moderation_case_id)
    |> foreign_key_constraint(:rule_id)
  end
end
