defmodule CommunityHealth.Repo.Migrations.CreateReputationEvents do
  use Ecto.Migration

  def change do
    create table(:reputation_events) do
      add :community_id, references(:communities, on_delete: :delete_all), null: false
      add :actor_external_id, :string, null: false
      add :action_type, :string, null: false
      add :points, :integer, null: false
      # One-to-one with the action that generated it — keeps awarding
      # idempotent the same way `community_actions` itself is idempotent on
      # event_key: replaying an action (e.g. an Oban retry) can never award
      # reputation twice for it.
      add :community_action_id, references(:community_actions, on_delete: :delete_all),
        null: false

      add :occurred_at, :utc_datetime, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:reputation_events, [:community_action_id])
    create index(:reputation_events, [:community_id, :actor_external_id])
  end
end
