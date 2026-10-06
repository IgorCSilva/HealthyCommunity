defmodule CommunityHealthWeb.RoleControllerTest do
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
    conn = build_conn() |> get(~p"/v1/communities/default/members/user-1/role-progress/guardian")
    assert json_response(conn, 401)
  end

  test "returns each requirement with its threshold and current value", %{conn: conn} do
    conn = get(conn, ~p"/v1/communities/default/members/user-1/role-progress/guardian")

    assert %{"role_code" => "guardian", "eligible" => false, "requirements" => requirements} =
             json_response(conn, 200)

    assert length(requirements) == 4
    assert Enum.all?(requirements, &Map.has_key?(&1, "threshold"))
    assert Enum.all?(requirements, &Map.has_key?(&1, "current"))
  end

  test "422s for a role with no defined eligibility criteria", %{conn: conn} do
    conn = get(conn, ~p"/v1/communities/default/members/user-1/role-progress/moderator")
    assert json_response(conn, 422)
  end

  test "404s for a non-member", %{conn: conn} do
    conn = get(conn, ~p"/v1/communities/default/members/nobody/role-progress/guardian")
    assert json_response(conn, 404)
  end

  test "404s when the community hasn't been registered", %{conn: conn} do
    conn = get(conn, ~p"/v1/communities/nonexistent/members/user-1/role-progress/guardian")
    assert json_response(conn, 404)
  end
end
