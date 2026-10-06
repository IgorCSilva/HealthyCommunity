defmodule CommunityHealthWeb.ReputationControllerTest do
  use CommunityHealthWeb.ConnCase, async: true

  alias CommunityHealth.{Actions, Communities, Platforms, Reputation}

  setup %{conn: conn} do
    {:ok, platform, token} = Platforms.register_platform("Underlined")
    {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")
    {:ok, _rule} = Reputation.create_rule(community, %{action_type: "CREATE", points: 60})

    conn = put_req_header(conn, "authorization", "Bearer #{token}")

    %{conn: conn, platform: platform, community: community}
  end

  describe "authentication" do
    test "rejects requests with no Authorization header" do
      conn = build_conn() |> get(~p"/v1/communities/default/members/user-1/reputation")
      assert json_response(conn, 401)
    end
  end

  describe "GET /v1/communities/:community_ref/members/:actor_ref/reputation" do
    test "returns score 0, level 1 for an actor with no reputation events", %{conn: conn} do
      conn = get(conn, ~p"/v1/communities/default/members/user-1/reputation")
      assert json_response(conn, 200) == %{"actor_external_id" => "user-1", "score" => 0, "level" => 1}
    end

    test "reflects the rolled-up score after a matching action is recorded", %{
      conn: conn,
      platform: platform,
      community: community
    } do
      {:ok, _action} =
        Actions.record_action(platform, community, %{
          actor_external_id: "user-1",
          action_type: "CREATE",
          resource_type: "post",
          resource_ref: "post-1",
          event_key: "post:create:post-1"
        })

      Reputation.rollup_score(community.id, "user-1")

      conn = get(conn, ~p"/v1/communities/default/members/user-1/reputation")
      assert json_response(conn, 200) == %{"actor_external_id" => "user-1", "score" => 60, "level" => 3}
    end

    test "404s when the community hasn't been registered", %{conn: conn} do
      conn = get(conn, ~p"/v1/communities/nonexistent/members/user-1/reputation")
      assert json_response(conn, 404)
    end
  end
end
