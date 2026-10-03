defmodule CommunityHealthWeb.CommunityAndMembershipTest do
  use CommunityHealthWeb.ConnCase, async: true

  alias CommunityHealth.Platforms

  setup do
    {:ok, platform, token} = Platforms.register_platform("Underlined")
    %{platform: platform, token: token}
  end

  describe "authentication" do
    test "rejects requests with no Authorization header", %{conn: conn} do
      conn = post(conn, ~p"/v1/communities", %{external_ref: "default", name: "Underlined"})
      assert json_response(conn, 401)
    end

    test "rejects requests with an invalid token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer not-a-real-token")
        |> post(~p"/v1/communities", %{external_ref: "default", name: "Underlined"})

      assert json_response(conn, 401)
    end
  end

  describe "POST /v1/communities" do
    test "registers a community for the authenticated platform", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/v1/communities", %{external_ref: "default", name: "Underlined"})

      assert %{"external_ref" => "default", "name" => "Underlined"} = json_response(conn, 200)
    end
  end

  describe "PUT /v1/communities/:community_ref/members/:actor_ref" do
    test "ensures membership once the community exists", %{conn: conn, token: token} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      post(conn, ~p"/v1/communities", %{external_ref: "default", name: "Underlined"})

      conn = put(conn, ~p"/v1/communities/default/members/user-1")

      assert %{"community_external_ref" => "default", "actor_external_id" => "user-1"} =
               json_response(conn, 200)
    end

    test "404s when the community hasn't been registered yet", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put(~p"/v1/communities/nonexistent/members/user-1")

      assert json_response(conn, 404)
    end
  end
end
