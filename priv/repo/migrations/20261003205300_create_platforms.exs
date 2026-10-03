defmodule CommunityHealth.Repo.Migrations.CreatePlatforms do
  use Ecto.Migration

  def change do
    create table(:platforms) do
      add :name, :string, null: false
      add :code, :string, null: false

      timestamps()
    end

    create unique_index(:platforms, [:code])
  end
end
