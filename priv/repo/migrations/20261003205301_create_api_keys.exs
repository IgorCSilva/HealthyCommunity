defmodule CommunityHealth.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys) do
      add :platform_id, references(:platforms, on_delete: :delete_all), null: false
      add :token_hash, :string, null: false
      add :revoked_at, :utc_datetime

      timestamps()
    end

    create unique_index(:api_keys, [:token_hash])
    create index(:api_keys, [:platform_id])
  end
end
