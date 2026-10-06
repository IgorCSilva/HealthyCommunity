defmodule CommunityHealth.Repo.Migrations.CreateReputationRules do
  use Ecto.Migration

  def change do
    create table(:reputation_rules) do
      add :community_id, references(:communities, on_delete: :delete_all), null: false
      add :action_type, :string, null: false
      add :points, :integer, null: false
      # Max points this rule can contribute to a single actor per UTC day —
      # the "simply use daily caps" diminishing-returns approach from
      # mvp_structure.md §16, chosen over tiered per-action reduction to
      # keep the rollup's math a single clamp instead of a bucketed curve.
      add :daily_cap, :integer
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:reputation_rules, [:community_id, :action_type])
  end
end
