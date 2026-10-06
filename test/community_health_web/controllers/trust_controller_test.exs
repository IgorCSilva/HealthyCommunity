defmodule CommunityHealthWeb.TrustControllerTest do
  use CommunityHealthWeb.ConnCase, async: true

  alias CommunityHealth.{Communities, Platforms}

  setup %{conn: conn} do
    {:ok, platform, token} = Platforms.register_platform("Underlined")
    {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")
    {:ok, _member} = Communities.ensure_member(community, "user-1")

    conn = put_req_header(conn, "authorization", "Bearer #{token}")

    %{conn: conn, community: community}
  end

  test "rejects requests with no Authorization header" do
    conn = build_conn() |> get(~p"/v1/communities/default/members/user-1/trust")
    assert json_response(conn, 401)
  end

  test "returns low trust for a brand-new member", %{conn: conn} do
    conn = get(conn, ~p"/v1/communities/default/members/user-1/trust")

    assert %{"actor_external_id" => "user-1", "trust_level" => "low", "account_age_days" => 0} =
             json_response(conn, 200)
  end

  test "404s for a non-member", %{conn: conn} do
    conn = get(conn, ~p"/v1/communities/default/members/nobody/trust")
    assert json_response(conn, 404)
  end

  test "404s when the community hasn't been registered", %{conn: conn} do
    conn = get(conn, ~p"/v1/communities/nonexistent/members/user-1/trust")
    assert json_response(conn, 404)
  end
end
