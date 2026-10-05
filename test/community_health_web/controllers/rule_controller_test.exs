defmodule CommunityHealthWeb.RuleControllerTest do
  use CommunityHealthWeb.ConnCase, async: true

  alias CommunityHealth.{Communities, Platforms, Rules}

  setup %{conn: conn} do
    {:ok, platform, token} = Platforms.register_platform("Underlined")
    {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")

    conn = conn |> put_req_header("authorization", "Bearer #{token}")

    %{conn: conn, platform: platform, community: community, token: token}
  end

  describe "authentication" do
    test "rejects requests with no Authorization header" do
      conn = build_conn() |> get(~p"/v1/communities/default/rules")
      assert json_response(conn, 401)
    end
  end

  describe "GET /v1/communities/:community_ref/rules" do
    test "lists only active rules", %{conn: conn, community: community} do
      {:ok, _} = Rules.create_rule(community, %{code: "SPAM", name: "Spam", severity: "low"})

      {:ok, _} =
        Rules.create_rule(community, %{
          code: "OLD_RULE",
          name: "Old rule",
          severity: "low",
          active: false
        })

      conn = get(conn, ~p"/v1/communities/default/rules")

      assert %{"data" => [%{"code" => "SPAM", "severity" => "low"}]} = json_response(conn, 200)
    end

    test "404s for an unregistered community", %{conn: conn} do
      conn = get(conn, ~p"/v1/communities/nonexistent/rules")
      assert json_response(conn, 404)
    end
  end
end
