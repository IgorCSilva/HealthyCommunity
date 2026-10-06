defmodule CommunityHealth.Repo.Migrations.AddRoleIdToCommunityMembers do
  use Ecto.Migration

  def change do
    alter table(:community_members) do
      # Nullable, not DB-defaulted: `Communities.ensure_member/2` assigns the
      # "reader" role explicitly on first insert (role ids are ordinary
      # serials, only known once the seed migration has run — no fixed
      # constant to default against at the column level).
      add :role_id, references(:roles, on_delete: :nilify_all)
    end

    create index(:community_members, [:role_id])
  end
end
