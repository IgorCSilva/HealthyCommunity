defmodule CommunityHealth.Repo.Migrations.CreateCommunityRules do
  use Ecto.Migration

  def change do
    create table(:community_rules) do
      add :community_id, references(:communities, on_delete: :delete_all), null: false
      add :code, :string, null: false
      add :name, :string, null: false
      add :description, :string
      add :severity, :string, null: false
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:community_rules, [:community_id, :code])
  end
end
