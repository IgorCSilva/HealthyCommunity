defmodule CommunityHealth.Repo.Migrations.CreateModerationActions do
  use Ecto.Migration

  def change do
    create table(:moderation_actions) do
      add :moderation_decision_id, references(:moderation_decisions, on_delete: :delete_all),
        null: false

      # The case's reported_actor_external_id, copied onto the action for a
      # content-only action type (content_removed/content_hidden/
      # comment_locked) this stays nil when CH never derived an author.
      add :target_actor_external_id, :string
      add :action_type, :string, null: false
      add :duration_days, :integer
      add :reason, :string, null: false

      timestamps(updated_at: false)
    end

    create index(:moderation_actions, [:moderation_decision_id])
    create index(:moderation_actions, [:target_actor_external_id])
  end
end
