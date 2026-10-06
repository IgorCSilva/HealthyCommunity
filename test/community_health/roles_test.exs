defmodule CommunityHealth.RolesTest do
  use CommunityHealth.DataCase, async: true

  alias CommunityHealth.{Actions, Communities, Moderation, Platforms, Reputation, Roles, Rules}

  setup do
    {:ok, platform, _token} = Platforms.register_platform("Underlined")
    {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")
    {:ok, _member} = Communities.ensure_member(community, "user-1")

    %{platform: platform, community: community}
  end

  describe "ensure_member/2 default role" do
    test "a fresh member starts as reader", %{community: community} do
      assert Roles.role_code_for(community, "user-1") == "reader"
    end
  end

  describe "list_roles/0 and permissions_for/1" do
    test "the five seeded roles exist" do
      assert Enum.map(Roles.list_roles(), & &1.code) ==
               ~w(admin contributor guardian moderator reader)
    end

    test "reader has the base three permissions, not review_reports" do
      reader = Roles.get_role_by_code("reader")
      assert Roles.permissions_for(reader) == ~w(create_comment create_post report_content)
      refute Roles.has_permission?(reader, "review_reports")
    end

    test "guardian adds review_reports on top of reader's permissions" do
      guardian = Roles.get_role_by_code("guardian")
      assert Roles.has_permission?(guardian, "review_reports")
      assert Roles.has_permission?(guardian, "create_post")
      refute Roles.has_permission?(guardian, "hide_content")
    end

    test "moderator adds moderation permissions on top of guardian's" do
      moderator = Roles.get_role_by_code("moderator")
      assert Roles.has_permission?(moderator, "hide_content")
      assert Roles.has_permission?(moderator, "remove_content")
      assert Roles.has_permission?(moderator, "suspend_user")
      refute Roles.has_permission?(moderator, "ban_user")
    end

    test "admin has every permission" do
      admin = Roles.get_role_by_code("admin")
      assert length(Roles.permissions_for(admin)) == 10
    end
  end

  describe "set_role/3" do
    test "promotes a member to a new role", %{community: community} do
      assert {:ok, _membership} = Roles.set_role(community, "user-1", "guardian")
      assert Roles.role_code_for(community, "user-1") == "guardian"
    end

    test "errors when the actor isn't a member", %{community: community} do
      assert {:error, :actor_not_found} = Roles.set_role(community, "nobody", "guardian")
    end

    test "errors when the role code doesn't exist", %{community: community} do
      assert {:error, :role_not_found} = Roles.set_role(community, "user-1", "superadmin")
    end
  end

  describe "role_progress/3" do
    test "reports every requirement as unmet for a brand-new member", %{community: community} do
      assert {:ok, %{role_code: "guardian", eligible: false, requirements: requirements}} =
               Roles.role_progress(community, "user-1", "guardian")

      assert Enum.find(requirements, &(&1.code == "account_age_days")).met == false
      assert Enum.find(requirements, &(&1.code == "reputation_score")).current == 0
    end

    test "becomes eligible once every threshold is met", %{
      platform: platform,
      community: community
    } do
      {:ok, _rule} = Reputation.create_rule(community, %{action_type: "CREATE", points: 30})

      for n <- 1..10 do
        {:ok, _} =
          Actions.record_action(platform, community, %{
            actor_external_id: "user-1",
            action_type: "CREATE",
            resource_type: "post",
            resource_ref: "post-#{n}",
            event_key: "post:create:post-#{n}"
          })
      end

      Reputation.rollup_score(community.id, "user-1")

      # Back-date the membership row so the account-age requirement is met too.
      member = Communities.get_member(community, "user-1")

      backdated =
        NaiveDateTime.add(NaiveDateTime.utc_now(), -31 * 24 * 60 * 60, :second)
        |> NaiveDateTime.truncate(:second)

      Ecto.Changeset.change(member, inserted_at: backdated) |> CommunityHealth.Repo.update!()

      assert {:ok, %{eligible: true, requirements: requirements}} =
               Roles.role_progress(community, "user-1", "guardian")

      assert Enum.all?(requirements, & &1.met)
    end

    test "confirmed_violations comes from CH-Step 6/7's real moderation data, not a hard-coded 0",
         %{
           platform: platform,
           community: community
         } do
      {:ok, _rule} =
        Rules.create_rule(community, %{
          code: "PERSONAL_ATTACK",
          name: "Personal attack",
          severity: "low"
        })

      {:ok, _guardian} = Communities.ensure_member(community, "guardian-1")
      {:ok, _} = Roles.set_role(community, "guardian-1", "guardian")

      {:ok, _action} =
        Actions.record_action(platform, community, %{
          actor_external_id: "user-1",
          action_type: "CREATE",
          resource_type: "post",
          resource_ref: "post-1",
          event_key: "post:create:post-1"
        })

      {:ok, report} =
        CommunityHealth.Reports.submit_report(platform, community, %{
          reporter_external_id: "reporter-1",
          resource_type: "post",
          resource_ref: "post-1",
          reason: "PERSONAL_ATTACK"
        })

      moderation_case = Moderation.get_case_for_report(community, report.id)
      :ok = Moderation.assign_case_reviewer(moderation_case.id)

      {:ok, _decision} =
        Moderation.decide_case(community, moderation_case.id, %{
          reviewer_external_id: "guardian-1",
          decision: "violation"
        })

      assert {:ok, %{requirements: requirements}} =
               Roles.role_progress(community, "user-1", "guardian")

      assert Enum.find(requirements, &(&1.code == "confirmed_violations")).current == 1
    end

    test "returns :unsupported_role for a role with no defined criteria", %{community: community} do
      assert {:error, :unsupported_role} = Roles.role_progress(community, "user-1", "moderator")
    end

    test "returns :actor_not_found for a non-member", %{community: community} do
      assert {:error, :actor_not_found} = Roles.role_progress(community, "nobody", "guardian")
    end
  end
end
