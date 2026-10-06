defmodule CommunityHealth.Repo.Migrations.CreateModerationAppeals do
  use Ecto.Migration

  def change do
    create table(:moderation_appeals) do
      add :moderation_action_id, references(:moderation_actions, on_delete: :delete_all),
        null: false

      add :appellant_external_id, :string, null: false
      add :reason, :string, null: false
      add :status, :string, null: false, default: "pending"
      # Set once a different reviewer than the original decision's is
      # assigned (CH-Step 9's reviewer-assignment logic, reused here with
      # the original reviewer added to the exclusion set); stays the same
      # value once the appeal is resolved.
      add :reviewed_by, :string
      add :resolved_at, :utc_datetime

      timestamps()
    end

    # One appeal per action, replay-safe the same way reports are
    # idempotent on (platform, resource, reporter).
    create unique_index(:moderation_appeals, [:moderation_action_id])
    create index(:moderation_appeals, [:reviewed_by])
  end
end
