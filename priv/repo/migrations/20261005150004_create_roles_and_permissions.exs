defmodule CommunityHealth.Repo.Migrations.CreateRolesAndPermissions do
  use Ecto.Migration

  @moduledoc """
  CH-Step 9: a small, fixed role/permission taxonomy
  (mvp_structure.md §11-12) — unlike `community_rules`, these aren't
  per-community operator config, so they're seeded directly here instead
  of via a mix task, and are present in every environment (including
  tests) the moment this migration runs.
  """

  def change do
    create table(:roles) do
      add :code, :string, null: false
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:roles, [:code])

    create table(:permissions) do
      add :code, :string, null: false
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:permissions, [:code])

    create table(:role_permissions) do
      add :role_id, references(:roles, on_delete: :delete_all), null: false
      add :permission_id, references(:permissions, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:role_permissions, [:role_id, :permission_id])

    execute(
      """
      INSERT INTO roles (code, name, inserted_at, updated_at) VALUES
        ('reader', 'Reader', now(), now()),
        ('contributor', 'Contributor', now(), now()),
        ('guardian', 'Guardian', now(), now()),
        ('moderator', 'Moderator', now(), now()),
        ('admin', 'Admin', now(), now())
      """,
      "DELETE FROM roles"
    )

    execute(
      """
      INSERT INTO permissions (code, name, inserted_at, updated_at) VALUES
        ('create_post', 'Create post', now(), now()),
        ('create_comment', 'Create comment', now(), now()),
        ('report_content', 'Report content', now(), now()),
        ('review_reports', 'Review reports', now(), now()),
        ('hide_content', 'Hide content', now(), now()),
        ('remove_content', 'Remove content', now(), now()),
        ('suspend_user', 'Suspend user', now(), now()),
        ('ban_user', 'Ban user', now(), now()),
        ('manage_rules', 'Manage rules', now(), now()),
        ('manage_roles', 'Manage roles', now(), now())
      """,
      "DELETE FROM permissions"
    )

    execute(
      """
      INSERT INTO role_permissions (role_id, permission_id, inserted_at, updated_at)
      SELECT r.id, p.id, now(), now() FROM roles r, permissions p
      WHERE (r.code = 'reader' AND p.code IN ('create_post', 'create_comment', 'report_content'))
         OR (r.code = 'contributor' AND p.code IN ('create_post', 'create_comment', 'report_content'))
         OR (r.code = 'guardian' AND p.code IN ('create_post', 'create_comment', 'report_content', 'review_reports'))
         OR (r.code = 'moderator' AND p.code IN (
               'create_post', 'create_comment', 'report_content', 'review_reports',
               'hide_content', 'remove_content', 'suspend_user'
             ))
         OR (r.code = 'admin')
      """,
      "DELETE FROM role_permissions"
    )
  end
end
