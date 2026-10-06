defmodule CommunityHealth.TrustTest do
  use CommunityHealth.DataCase, async: true

  alias CommunityHealth.{
    Actions,
    Communities,
    Moderation,
    Platforms,
    Reputation,
    Roles,
    Rules,
    Trust
  }

  setup do
    {:ok, platform, _token} = Platforms.register_platform("Underlined")
    {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")
    {:ok, _member} = Communities.ensure_member(community, "user-1")

    %{platform: platform, community: community}
  end

  describe "get_trust_level/2" do
    test "a brand-new member is low trust", %{community: community} do
      assert {:ok, %{trust_level: "low", account_age_days: 0, reputation_score: 0}} =
               Trust.get_trust_level(community, "user-1")
    end

    test "errors for a non-member", %{community: community} do
      assert {:error, :actor_not_found} = Trust.get_trust_level(community, "nobody")
    end

    test "reaches medium trust with a week of age and modest reputation", %{community: community} do
      backdate_member(community, "user-1", 8)
      set_score(community, "user-1", 15)

      assert {:ok, %{trust_level: "medium"}} = Trust.get_trust_level(community, "user-1")
    end

    test "reaches high trust with 30+ days of age and strong reputation", %{community: community} do
      backdate_member(community, "user-1", 31)
      set_score(community, "user-1", 150)

      assert {:ok, %{trust_level: "high"}} = Trust.get_trust_level(community, "user-1")
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

      {:ok, decision} =
        Moderation.decide_case(community, moderation_case.id, %{
          reviewer_external_id: "guardian-1",
          decision: "violation"
        })

      assert {:ok, %{confirmed_violations: 1}} = Trust.get_trust_level(community, "user-1")

      {:ok, action} =
        Moderation.create_action(community, decision.id, %{action_type: "warning", reason: "..."})

      {:ok, appeal} =
        Moderation.file_appeal(community, action.id, %{
          appellant_external_id: "user-1",
          reason: "..."
        })

      # No second guardian exists, so the appeal never gets a reviewer
      # assigned here — resolve it directly to isolate what Trust reads.
      {:ok, _} =
        appeal
        |> Moderation.ModerationAppeal.resolve_changeset(%{
          status: "upheld",
          resolved_at: DateTime.utc_now()
        })
        |> CommunityHealth.Repo.update()

      assert {:ok, %{confirmed_violations: 0}} = Trust.get_trust_level(community, "user-1")
    end

    defp backdate_member(community, actor_external_id, days) do
      member = Communities.get_member(community, actor_external_id)

      backdated =
        NaiveDateTime.add(NaiveDateTime.utc_now(), -days * 24 * 60 * 60, :second)
        |> NaiveDateTime.truncate(:second)

      Ecto.Changeset.change(member, inserted_at: backdated) |> CommunityHealth.Repo.update!()
    end

    defp set_score(community, actor_external_id, score) do
      %Reputation.ReputationScore{}
      |> Reputation.ReputationScore.changeset(%{
        community_id: community.id,
        actor_external_id: actor_external_id,
        score: score
      })
      |> CommunityHealth.Repo.insert!()
    end
  end
end
