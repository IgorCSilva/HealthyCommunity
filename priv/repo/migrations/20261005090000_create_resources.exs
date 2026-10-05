defmodule CommunityHealth.Repo.Migrations.CreateResources do
  use Ecto.Migration

  def change do
    create table(:resources) do
      add :platform_id, references(:platforms, on_delete: :delete_all), null: false
      add :resource_type, :string, null: false
      add :external_ref, :string, null: false

      timestamps()
    end

    create unique_index(:resources, [:platform_id, :resource_type, :external_ref])
  end
end
