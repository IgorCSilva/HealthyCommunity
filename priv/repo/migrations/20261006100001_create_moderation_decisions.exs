defmodule CommunityHealth.Repo.Migrations.CreateModerationDecisions do
  use Ecto.Migration

  def change do
    create table(:moderation_decisions) do
      add :moderation_case_id, references(:moderation_cases, on_delete: :delete_all), null: false
      add :reviewer_external_id, :string, null: false
      add :decision, :string, null: false
      add :rule_id, references(:community_rules, on_delete: :nilify_all)
      add :notes, :string

      timestamps(updated_at: false)
    end

    # One case gets exactly one decision for MVP — a reconsideration goes
    # through the appeal flow (CH-Step 7), not a second decision on the
    # same case.
    create unique_index(:moderation_decisions, [:moderation_case_id])
  end
end
