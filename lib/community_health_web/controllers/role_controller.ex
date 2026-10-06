defmodule CommunityHealthWeb.RoleController do
  use CommunityHealthWeb, :controller

  alias CommunityHealth.Communities
  alias CommunityHealth.Roles

  def role_progress(conn, %{
        "community_ref" => community_ref,
        "actor_ref" => actor_ref,
        "role_code" => role_code
      }) do
    case Communities.get_community(conn.assigns.current_platform, community_ref) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Community not found"}})

      community ->
        case Roles.role_progress(community, actor_ref, role_code) do
          {:ok, progress} ->
            json(conn, progress)

          {:error, :actor_not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{errors: %{detail: "Actor not found"}})

          {:error, :unsupported_role} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{errors: %{detail: "No eligibility criteria defined for this role"}})
        end
    end
  end
end
