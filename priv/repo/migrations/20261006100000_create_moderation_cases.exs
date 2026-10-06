defmodule CommunityHealth.Repo.Migrations.CreateModerationCases do
  use Ecto.Migration

  def change do
    create table(:moderation_cases) do
      add :report_id, references(:reports, on_delete: :delete_all), null: false
      add :community_id, references(:communities, on_delete: :delete_all), null: false
      # Resolved once, at case-creation time, from the reported resource's
      # earliest community_action (its creation event) — CH's resources
      # table deliberately has no owner column (decoupled_healthy_system.md
      # §13), so this is the generic way to recover "who made this" without
      # one. Nullable: a resource reported before CH ever recorded any
      # action against it (e.g. a backfill gap) has no derivable author.
      add :reported_actor_external_id, :string
      # Copied from the cited rule's severity at filing time, so a rule
      # changed later never re-routes a case already opened under it.
      add :severity, :string, null: false
      add :reviewer_external_id, :string
      add :status, :string, null: false, default: "pending"

      timestamps()
    end

    create unique_index(:moderation_cases, [:report_id])
    create index(:moderation_cases, [:community_id, :status])
    create index(:moderation_cases, [:reviewer_external_id])
  end
end
