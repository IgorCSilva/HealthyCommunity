defmodule CommunityHealthWeb.EventControllerTest do
  use CommunityHealthWeb.ConnCase, async: true

  alias CommunityHealth.Platforms

  setup %{conn: conn} do
    {:ok, platform, token} = Platforms.register_platform("Underlined")

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(~p"/v1/communities", %{external_ref: "default", name: "Underlined"})

    %{conn: conn, platform: platform, token: token}
  end

  @params %{
    "community_ref" => "default",
    "actor_id" => "user-1",
    "action_type" => "CREATE",
    "resource_type" => "post",
    "resource_ref" => "post-1",
    "event_key" => "post:create:post-1"
  }

  describe "authentication" do
    test "rejects requests with no Authorization header" do
      conn = build_conn() |> post(~p"/v1/events", @params)
      assert json_response(conn, 401)
    end
  end

  describe "POST /v1/events" do
    test "records a new action", %{conn: conn} do
      conn = post(conn, ~p"/v1/events", @params)

      assert %{
               "event_key" => "post:create:post-1",
               "action_type" => "CREATE",
               "resource_type" => "post",
               "resource_ref" => "post-1",
               "actor_external_id" => "user-1"
             } = json_response(conn, 200)
    end

    test "is idempotent on event_key — replaying it returns the original, not a duplicate", %{
      conn: conn,
      token: token
    } do
      first = post(conn, ~p"/v1/events", @params) |> json_response(200)

      second =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/v1/events", %{@params | "action_type" => "DIFFERENT"})
        |> json_response(200)

      assert first["id"] == second["id"]
      assert second["action_type"] == "CREATE"
    end

    test "404s when the community hasn't been registered yet", %{conn: conn} do
      conn = post(conn, ~p"/v1/events", %{@params | "community_ref" => "nonexistent"})
      assert json_response(conn, 404)
    end
  end
end
