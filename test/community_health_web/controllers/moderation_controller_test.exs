defmodule CommunityHealthWeb.ModerationControllerTest do
  use CommunityHealthWeb.ConnCase, async: true

  alias CommunityHealth.{Actions, Communities, Moderation, Platforms, Roles, Rules}

  setup %{conn: conn} do
    {:ok, platform, token} = Platforms.register_platform("Underlined")
    {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")

    {:ok, _rule} =
      Rules.create_rule(community, %{
        code: "PERSONAL_ATTACK",
        name: "Personal attack",
        severity: "low"
      })

    {:ok, _member} = Communities.ensure_member(community, "guardian-1")
    {:ok, _} = Roles.set_role(community, "guardian-1", "guardian")

    {:ok, _action} =
      Actions.record_action(platform, community, %{
        actor_external_id: "author-1",
        action_type: "CREATE",
        resource_type: "post",
        resource_ref: "post-1",
        event_key: "post:create:post-1"
      })

    conn = put_req_header(conn, "authorization", "Bearer #{token}")

    %{conn: conn, platform: platform, community: community}
  end

  defp file_report(conn) do
    post(conn, ~p"/v1/reports", %{
      "community_ref" => "default",
      "reporter_id" => "reporter-1",
      "resource_type" => "post",
      "resource_ref" => "post-1",
      "reason" => "PERSONAL_ATTACK"
    })
    |> json_response(200)
  end

  describe "authentication" do
    test "every moderation route rejects requests with no Authorization header" do
      assert build_conn() |> get(~p"/v1/communities/default/reports/1/case") |> json_response(401)

      assert build_conn()
             |> post(~p"/v1/communities/default/cases/1/decisions", %{})
             |> json_response(401)

      assert build_conn()
             |> post(~p"/v1/communities/default/decisions/1/actions", %{})
             |> json_response(401)

      assert build_conn()
             |> post(~p"/v1/communities/default/actions/1/appeals", %{})
             |> json_response(401)

      assert build_conn()
             |> post(~p"/v1/communities/default/appeals/1/resolve", %{})
             |> json_response(401)
    end
  end

  describe "GET /v1/communities/:community_ref/reports/:report_id/case" do
    test "shows the case opened for a report, including its assigned reviewer", %{
      conn: conn,
      community: community
    } do
      report = file_report(conn)

      case_id = Moderation.get_case_for_report(community, report["id"]).id
      :ok = Moderation.assign_case_reviewer(case_id)

      conn = get(conn, ~p"/v1/communities/default/reports/#{report["id"]}/case")

      assert %{
               "status" => "assigned",
               "severity" => "low",
               "reviewer_external_id" => "guardian-1",
               "reported_actor_external_id" => "author-1"
             } = json_response(conn, 200)
    end

    test "404s when no case exists for that report id", %{conn: conn} do
      conn = get(conn, ~p"/v1/communities/default/reports/999999/case")
      assert json_response(conn, 404)
    end

    test "404s when the community hasn't been registered", %{conn: conn} do
      conn = get(conn, ~p"/v1/communities/nonexistent/reports/1/case")
      assert json_response(conn, 404)
    end
  end

  describe "POST /v1/communities/:community_ref/cases/:case_id/decisions" do
    setup %{conn: conn, community: community} do
      report = file_report(conn)
      moderation_case = Moderation.get_case_for_report(community, report["id"])
      :ok = Moderation.assign_case_reviewer(moderation_case.id)

      %{case_id: moderation_case.id}
    end

    test "records a decision from the assigned reviewer", %{conn: conn, case_id: case_id} do
      conn =
        post(conn, ~p"/v1/communities/default/cases/#{case_id}/decisions", %{
          "reviewer_external_id" => "guardian-1",
          "decision" => "violation",
          "notes" => "Attacks the reader personally."
        })

      assert %{"decision" => "violation", "moderation_case_id" => ^case_id} =
               json_response(conn, 200)
    end

    test "403s when the reviewer isn't the one assigned", %{conn: conn, case_id: case_id} do
      conn =
        post(conn, ~p"/v1/communities/default/cases/#{case_id}/decisions", %{
          "reviewer_external_id" => "someone-else",
          "decision" => "violation"
        })

      assert json_response(conn, 403)
    end

    test "422s for an invalid decision value", %{conn: conn, case_id: case_id} do
      conn =
        post(conn, ~p"/v1/communities/default/cases/#{case_id}/decisions", %{
          "reviewer_external_id" => "guardian-1",
          "decision" => "not_a_real_decision"
        })

      assert json_response(conn, 422)
    end

    test "404s for a case that doesn't exist", %{conn: conn} do
      conn =
        post(conn, ~p"/v1/communities/default/cases/999999/decisions", %{
          "reviewer_external_id" => "guardian-1",
          "decision" => "violation"
        })

      assert json_response(conn, 404)
    end
  end

  describe "POST /v1/communities/:community_ref/decisions/:decision_id/actions" do
    setup %{conn: conn, community: community} do
      report = file_report(conn)
      moderation_case = Moderation.get_case_for_report(community, report["id"])
      :ok = Moderation.assign_case_reviewer(moderation_case.id)

      {:ok, decision} =
        Moderation.decide_case(community, moderation_case.id, %{
          reviewer_external_id: "guardian-1",
          decision: "violation"
        })

      %{decision_id: decision.id}
    end

    test "records an action against a confirmed violation", %{
      conn: conn,
      decision_id: decision_id
    } do
      conn =
        post(conn, ~p"/v1/communities/default/decisions/#{decision_id}/actions", %{
          "action_type" => "warning",
          "reason" => "First offense; a warning is proportionate."
        })

      assert %{
               "action_type" => "warning",
               "target_actor_external_id" => "author-1",
               "moderation_decision_id" => ^decision_id
             } = json_response(conn, 200)
    end

    test "422s for an action type that needs a target actor CH couldn't derive", %{
      conn: conn,
      platform: platform,
      community: community
    } do
      {:ok, report} =
        CommunityHealth.Reports.submit_report(platform, community, %{
          reporter_external_id: "reporter-2",
          resource_type: "post",
          resource_ref: "post-never-seen",
          reason: "PERSONAL_ATTACK"
        })

      moderation_case = Moderation.get_case_for_report(community, report.id)
      :ok = Moderation.assign_case_reviewer(moderation_case.id)

      {:ok, decision} =
        Moderation.decide_case(community, moderation_case.id, %{
          reviewer_external_id: "guardian-1",
          decision: "violation"
        })

      conn =
        post(conn, ~p"/v1/communities/default/decisions/#{decision.id}/actions", %{
          "action_type" => "warning",
          "reason" => "..."
        })

      assert json_response(conn, 422)
    end
  end

  describe "appeals: POST .../actions/:action_id/appeals and POST .../appeals/:appeal_id/resolve" do
    setup %{conn: conn, community: community} do
      {:ok, _member} = Communities.ensure_member(community, "guardian-2")
      {:ok, _} = Roles.set_role(community, "guardian-2", "guardian")

      report = file_report(conn)
      moderation_case = Moderation.get_case_for_report(community, report["id"])
      :ok = Moderation.assign_case_reviewer(moderation_case.id)
      original_reviewer = Moderation.get_case(community, moderation_case.id).reviewer_external_id

      {:ok, decision} =
        Moderation.decide_case(community, moderation_case.id, %{
          reviewer_external_id: original_reviewer,
          decision: "violation"
        })

      {:ok, action} =
        Moderation.create_action(community, decision.id, %{action_type: "warning", reason: "..."})

      %{action_id: action.id, original_reviewer: original_reviewer}
    end

    test "the target actor can file an appeal", %{conn: conn, action_id: action_id} do
      conn =
        post(conn, ~p"/v1/communities/default/actions/#{action_id}/appeals", %{
          "appellant_external_id" => "author-1",
          "reason" => "I was discussing the interpretation, not the person."
        })

      assert %{"status" => "pending", "appellant_external_id" => "author-1"} =
               json_response(conn, 200)
    end

    test "403s when the appellant isn't the action's target", %{conn: conn, action_id: action_id} do
      conn =
        post(conn, ~p"/v1/communities/default/actions/#{action_id}/appeals", %{
          "appellant_external_id" => "someone-else",
          "reason" => "..."
        })

      assert json_response(conn, 403)
    end

    test "resolving an appeal requires the assigned (necessarily different) reviewer", %{
      conn: conn,
      community: community,
      action_id: action_id,
      original_reviewer: original_reviewer
    } do
      appeal =
        post(conn, ~p"/v1/communities/default/actions/#{action_id}/appeals", %{
          "appellant_external_id" => "author-1",
          "reason" => "..."
        })
        |> json_response(200)

      :ok = Moderation.assign_appeal_reviewer(appeal["id"])
      assigned = Moderation.get_appeal(community, appeal["id"]).reviewed_by

      assert assigned != original_reviewer

      rejected =
        post(conn, ~p"/v1/communities/default/appeals/#{appeal["id"]}/resolve", %{
          "reviewer_external_id" => original_reviewer,
          "status" => "upheld"
        })

      assert json_response(rejected, 403)

      resolved =
        post(conn, ~p"/v1/communities/default/appeals/#{appeal["id"]}/resolve", %{
          "reviewer_external_id" => assigned,
          "status" => "upheld"
        })

      assert %{"status" => "upheld"} = json_response(resolved, 200)
    end
  end
end
