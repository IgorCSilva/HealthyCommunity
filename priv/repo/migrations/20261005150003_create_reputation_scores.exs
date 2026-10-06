defmodule CommunityHealth.Repo.Migrations.CreateReputationScores do
  use Ecto.Migration

  def change do
    create table(:reputation_scores) do
      add :community_id, references(:communities, on_delete: :delete_all), null: false
      add :actor_external_id, :string, null: false
      add :score, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:reputation_scores, [:community_id, :actor_external_id])
  end
end
