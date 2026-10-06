defmodule CommunityHealthWeb.TrustController do
  use CommunityHealthWeb, :controller

  alias CommunityHealth.Communities
  alias CommunityHealth.Trust

  def show(conn, %{"community_ref" => community_ref, "actor_ref" => actor_ref}) do
    case Communities.get_community(conn.assigns.current_platform, community_ref) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Community not found"}})

      community ->
        case Trust.get_trust_level(community, actor_ref) do
          {:ok, trust} ->
            json(conn, Map.put(trust, :actor_external_id, actor_ref))

          {:error, :actor_not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{errors: %{detail: "Actor not found"}})
        end
    end
  end
end
