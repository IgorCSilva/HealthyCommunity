defmodule CommunityHealth.Repo.Migrations.CreateCommunityActions do
  use Ecto.Migration

  def change do
    create table(:community_actions) do
      add :platform_id, references(:platforms, on_delete: :delete_all), null: false
      add :community_id, references(:communities, on_delete: :delete_all), null: false
      add :resource_id, references(:resources, on_delete: :delete_all), null: false
      add :actor_external_id, :string, null: false
      add :action_type, :string, null: false
      add :event_key, :string, null: false
      add :context, :map, default: %{}
      add :occurred_at, :utc_datetime, null: false

      timestamps(updated_at: false)
    end

    # The idempotency contract CH-Step 3 promises: a caller-supplied
    # event_key, scoped per platform, is the single source of truth for
    # "have I already recorded this" — retries/backfills insert the same
    # key and get the original row back, never a duplicate.
    create unique_index(:community_actions, [:platform_id, :event_key])
    create index(:community_actions, [:resource_id])
    create index(:community_actions, [:actor_external_id])
  end
end
