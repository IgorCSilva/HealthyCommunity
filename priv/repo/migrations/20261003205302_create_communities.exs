defmodule CommunityHealth.Repo.Migrations.CreateCommunities do
  use Ecto.Migration

  def change do
    create table(:communities) do
      add :platform_id, references(:platforms, on_delete: :delete_all), null: false
      add :external_ref, :string, null: false
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:communities, [:platform_id, :external_ref])
  end
end
