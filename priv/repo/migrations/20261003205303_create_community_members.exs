defmodule CommunityHealth.Repo.Migrations.CreateCommunityMembers do
  use Ecto.Migration

  def change do
    create table(:community_members) do
      add :community_id, references(:communities, on_delete: :delete_all), null: false
      add :actor_external_id, :string, null: false

      timestamps()
    end

    create unique_index(:community_members, [:community_id, :actor_external_id])
  end
end
