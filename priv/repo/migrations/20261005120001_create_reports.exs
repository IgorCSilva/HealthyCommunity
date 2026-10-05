defmodule CommunityHealth.Repo.Migrations.CreateReports do
  use Ecto.Migration

  def change do
    create table(:reports) do
      add :platform_id, references(:platforms, on_delete: :delete_all), null: false
      add :community_id, references(:communities, on_delete: :delete_all), null: false
      add :resource_id, references(:resources, on_delete: :delete_all), null: false
      add :reporter_external_id, :string, null: false
      add :reason, :string, null: false
      add :description, :string
      add :status, :string, null: false, default: "pending"

      timestamps()
    end

    # Idempotency contract for CH-Step 5: the same actor reporting the same
    # resource again (e.g. an Oban retry replaying a submission) returns the
    # original report instead of creating a duplicate.
    create unique_index(:reports, [:platform_id, :resource_id, :reporter_external_id])
    create index(:reports, [:community_id])
  end
end
