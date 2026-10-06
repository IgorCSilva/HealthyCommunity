defmodule CommunityHealthWeb.ReputationController do
  use CommunityHealthWeb, :controller

  alias CommunityHealth.Communities
  alias CommunityHealth.Reputation

  def show(conn, %{"community_ref" => community_ref, "actor_ref" => actor_ref}) do
    case Communities.get_community(conn.assigns.current_platform, community_ref) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Community not found"}})

      community ->
        %{score: score, level: level} = Reputation.get_score(community, actor_ref)
        json(conn, %{actor_external_id: actor_ref, score: score, level: level})
    end
  end
end
