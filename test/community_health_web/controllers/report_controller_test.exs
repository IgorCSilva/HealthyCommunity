defmodule CommunityHealthWeb.ReportControllerTest do
  use CommunityHealthWeb.ConnCase, async: true

  alias CommunityHealth.{Communities, Platforms, Rules}

  setup %{conn: conn} do
    {:ok, platform, token} = Platforms.register_platform("Underlined")
    {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")

    {:ok, _rule} =
      Rules.create_rule(community, %{
        code: "PERSONAL_ATTACK",
        name: "Personal attack",
        severity: "high"
      })

    conn = conn |> put_req_header("authorization", "Bearer #{token}")

    %{conn: conn, platform: platform, community: community, token: token}
  end

  @params %{
    "community_ref" => "default",
    "reporter_id" => "user-1",
    "resource_type" => "post",
    "resource_ref" => "post-1",
    "reason" => "PERSONAL_ATTACK",
    "description" => "Attacks another reader rather than discussing the book."
  }

  describe "authentication" do
    test "rejects requests with no Authorization header" do
      conn = build_conn() |> post(~p"/v1/reports", @params)
      assert json_response(conn, 401)
    end
  end

  describe "POST /v1/reports" do
    test "files a new report", %{conn: conn} do
      conn = post(conn, ~p"/v1/reports", @params)

      assert %{
               "reason" => "PERSONAL_ATTACK",
               "status" => "pending",
               "resource_type" => "post",
               "resource_ref" => "post-1",
               "reporter_external_id" => "user-1"
             } = json_response(conn, 200)
    end

    test "is idempotent on (resource, reporter) — replaying it returns the original, not a duplicate",
         %{conn: conn, token: token} do
      first = post(conn, ~p"/v1/reports", @params) |> json_response(200)

      second =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/v1/reports", %{@params | "description" => "different description"})
        |> json_response(200)

      assert first["id"] == second["id"]
    end

    test "404s when the community hasn't been registered yet", %{conn: conn} do
      conn = post(conn, ~p"/v1/reports", %{@params | "community_ref" => "nonexistent"})
      assert json_response(conn, 404)
    end

    test "422s when the reason isn't an active rule for the community", %{conn: conn} do
      conn = post(conn, ~p"/v1/reports", %{@params | "reason" => "NOT_A_RULE"})
      assert json_response(conn, 422)
    end
  end
end
