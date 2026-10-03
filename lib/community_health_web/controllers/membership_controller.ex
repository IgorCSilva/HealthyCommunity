defmodule CommunityHealthWeb.MembershipController do
  use CommunityHealthWeb, :controller

  alias CommunityHealth.Communities

  def ensure(conn, %{"community_ref" => community_ref, "actor_ref" => actor_ref}) do
    case Communities.get_community(conn.assigns.current_platform, community_ref) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Community not found"}})

      community ->
        {:ok, membership} = Communities.ensure_member(community, actor_ref)

        json(conn, %{
          community_external_ref: community_ref,
          actor_external_id: membership.actor_external_id
        })
    end
  end
end
