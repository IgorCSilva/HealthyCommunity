defmodule CommunityHealth.ModerationTest do
  use CommunityHealth.DataCase, async: true
  use Oban.Testing, repo: CommunityHealth.Repo

  alias CommunityHealth.{Actions, Communities, Moderation, Platforms, Reports, Roles, Rules}
  alias CommunityHealth.Moderation.{AppealAssignmentWorker, ReviewAssignmentWorker}

  setup do
    {:ok, platform, _token} = Platforms.register_platform("Underlined")
    {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")

    {:ok, _low} =
      Rules.create_rule(community, %{
        code: "PERSONAL_ATTACK",
        name: "Personal attack",
        severity: "low"
      })

    {:ok, _high} =
      Rules.create_rule(community, %{code: "THREAT", name: "Threat", severity: "high"})

    %{platform: platform, community: community}
  end

  defp author_post(platform, community, author, resource_ref) do
    {:ok, _action} =
      Actions.record_action(platform, community, %{
        actor_external_id: author,
        action_type: "CREATE",
        resource_type: "post",
        resource_ref: resource_ref,
        event_key: "post:create:#{resource_ref}"
      })
  end

  defp make_guardian(community, actor) do
    {:ok, _member} = Communities.ensure_member(community, actor)
    {:ok, _} = Roles.set_role(community, actor, "guardian")
  end

  defp make_moderator(community, actor) do
    {:ok, _member} = Communities.ensure_member(community, actor)
    {:ok, _} = Roles.set_role(community, actor, "moderator")
  end

  defp report!(platform, community, reporter, resource_ref, reason) do
    {:ok, report} =
      Reports.submit_report(platform, community, %{
        reporter_external_id: reporter,
        resource_type: "post",
        resource_ref: resource_ref,
        reason: reason
      })

    report
  end

  describe "open_case_for_report/2 (via Reports.submit_report/3)" do
    test "opens a pending case, severity from the rule, reported actor derived from the resource's creator",
         %{
           platform: platform,
           community: community
         } do
      author_post(platform, community, "author-1", "post-1")
      report = report!(platform, community, "reporter-1", "post-1", "PERSONAL_ATTACK")

      moderation_case = Moderation.get_case_for_report(community, report.id)

      assert moderation_case.status == "pending"
      assert moderation_case.severity == "low"
      assert moderation_case.reported_actor_external_id == "author-1"

      assert_enqueued(
        worker: ReviewAssignmentWorker,
        args: %{moderation_case_id: moderation_case.id}
      )
    end

    test "falls back to severity \"medium\" when the cited rule no longer exists", %{
      platform: platform,
      community: community
    } do
      {:ok, rule} =
        Rules.create_rule(community, %{code: "SPAM", name: "Spam", severity: "critical"})

      author_post(platform, community, "author-1", "post-2")

      report = report!(platform, community, "reporter-1", "post-2", "SPAM")
      Ecto.Changeset.change(rule, active: false) |> CommunityHealth.Repo.update!()

      # severity was already copied onto the case at filing time, so
      # deactivating the rule afterwards changes nothing retroactively
      moderation_case = Moderation.get_case_for_report(community, report.id)
      assert moderation_case.severity == "critical"
    end

    test "reported_actor_external_id is nil when CH never recorded an action for the resource", %{
      platform: platform,
      community: community
    } do
      report = report!(platform, community, "reporter-1", "post-never-seen", "PERSONAL_ATTACK")
      moderation_case = Moderation.get_case_for_report(community, report.id)

      assert moderation_case.reported_actor_external_id == nil
    end

    test "replaying the same report never opens a second case", %{
      platform: platform,
      community: community
    } do
      author_post(platform, community, "author-1", "post-3")
      report = report!(platform, community, "reporter-1", "post-3", "PERSONAL_ATTACK")

      # Resubmitting the identical report is itself idempotent (CH-Step 5),
      # so re-running the same submit_report call must still resolve to
      # exactly one case.
      {:ok, ^report} =
        Reports.submit_report(platform, community, %{
          reporter_external_id: "reporter-1",
          resource_type: "post",
          resource_ref: "post-3",
          reason: "PERSONAL_ATTACK"
        })

      assert Moderation.get_case_for_report(community, report.id) != nil
    end
  end

  describe "assign_case_reviewer/1" do
    test "assigns the only eligible guardian", %{platform: platform, community: community} do
      make_guardian(community, "guardian-1")
      author_post(platform, community, "author-1", "post-1")
      report = report!(platform, community, "reporter-1", "post-1", "PERSONAL_ATTACK")
      moderation_case = Moderation.get_case_for_report(community, report.id)

      assert :ok = Moderation.assign_case_reviewer(moderation_case.id)

      updated = Moderation.get_case(community, moderation_case.id)
      assert updated.status == "assigned"
      assert updated.reviewer_external_id == "guardian-1"
    end

    test "excludes the reporter from the reviewer pool", %{
      platform: platform,
      community: community
    } do
      make_guardian(community, "guardian-1")
      author_post(platform, community, "author-1", "post-1")
      # The sole guardian is also the reporter — no one else is eligible.
      report = report!(platform, community, "guardian-1", "post-1", "PERSONAL_ATTACK")
      moderation_case = Moderation.get_case_for_report(community, report.id)

      :ok = Moderation.assign_case_reviewer(moderation_case.id)

      updated = Moderation.get_case(community, moderation_case.id)
      assert updated.status == "pending"
      assert updated.reviewer_external_id == nil
    end

    test "excludes the reported actor (own content) from the reviewer pool", %{
      platform: platform,
      community: community
    } do
      # The sole guardian is also the content's author.
      make_guardian(community, "author-1")
      author_post(platform, community, "author-1", "post-1")
      report = report!(platform, community, "reporter-1", "post-1", "PERSONAL_ATTACK")
      moderation_case = Moderation.get_case_for_report(community, report.id)

      :ok = Moderation.assign_case_reviewer(moderation_case.id)

      updated = Moderation.get_case(community, moderation_case.id)
      assert updated.status == "pending"
      assert updated.reviewer_external_id == nil
    end

    test "excludes a reviewer who recently disputed with the reported actor", %{
      platform: platform,
      community: community
    } do
      make_guardian(community, "guardian-1")
      author_post(platform, community, "author-1", "post-1")
      author_post(platform, community, "author-1", "post-2")

      # guardian-1 reported author-1's content before — a "recent dispute".
      report1 = report!(platform, community, "guardian-1", "post-1", "PERSONAL_ATTACK")
      case1 = Moderation.get_case_for_report(community, report1.id)
      :ok = Moderation.assign_case_reviewer(case1.id)

      # A second, unrelated report against author-1 should no longer be
      # assignable to guardian-1, leaving no eligible reviewer at all
      # since guardian-1 is the only guardian in this community.
      report2 = report!(platform, community, "reporter-2", "post-2", "PERSONAL_ATTACK")
      case2 = Moderation.get_case_for_report(community, report2.id)
      :ok = Moderation.assign_case_reviewer(case2.id)

      updated = Moderation.get_case(community, case2.id)
      assert updated.status == "pending"
      assert updated.reviewer_external_id == nil
    end

    test "escalates high/critical severity to a moderator-permission reviewer over a guardian", %{
      platform: platform,
      community: community
    } do
      make_guardian(community, "guardian-1")
      make_moderator(community, "moderator-1")
      author_post(platform, community, "author-1", "post-1")

      report = report!(platform, community, "reporter-1", "post-1", "THREAT")
      moderation_case = Moderation.get_case_for_report(community, report.id)

      :ok = Moderation.assign_case_reviewer(moderation_case.id)

      updated = Moderation.get_case(community, moderation_case.id)
      assert updated.reviewer_external_id == "moderator-1"
    end

    test "leaves the case pending when no eligible reviewer exists at all", %{
      platform: platform,
      community: community
    } do
      author_post(platform, community, "author-1", "post-1")
      report = report!(platform, community, "reporter-1", "post-1", "PERSONAL_ATTACK")
      moderation_case = Moderation.get_case_for_report(community, report.id)

      :ok = Moderation.assign_case_reviewer(moderation_case.id)

      assert Moderation.get_case(community, moderation_case.id).status == "pending"
    end

    test "is a no-op once already assigned (replay-safe)", %{
      platform: platform,
      community: community
    } do
      make_guardian(community, "guardian-1")
      make_guardian(community, "guardian-2")
      author_post(platform, community, "author-1", "post-1")
      report = report!(platform, community, "reporter-1", "post-1", "PERSONAL_ATTACK")
      moderation_case = Moderation.get_case_for_report(community, report.id)

      :ok = Moderation.assign_case_reviewer(moderation_case.id)
      first_reviewer = Moderation.get_case(community, moderation_case.id).reviewer_external_id

      :ok = Moderation.assign_case_reviewer(moderation_case.id)

      assert Moderation.get_case(community, moderation_case.id).reviewer_external_id ==
               first_reviewer
    end
  end

  describe "decide_case/3" do
    setup %{platform: platform, community: community} do
      make_guardian(community, "guardian-1")
      author_post(platform, community, "author-1", "post-1")
      report = report!(platform, community, "reporter-1", "post-1", "PERSONAL_ATTACK")
      moderation_case = Moderation.get_case_for_report(community, report.id)
      :ok = Moderation.assign_case_reviewer(moderation_case.id)

      %{report: report, moderation_case: Moderation.get_case(community, moderation_case.id)}
    end

    test "records a violation decision, closes the case, and resolves the report", %{
      community: community,
      report: report,
      moderation_case: moderation_case
    } do
      assert {:ok, decision} =
               Moderation.decide_case(community, moderation_case.id, %{
                 reviewer_external_id: "guardian-1",
                 decision: "violation",
                 notes: "Attacks the reader, not the argument."
               })

      assert decision.decision == "violation"
      assert Moderation.get_case(community, moderation_case.id).status == "decided"

      assert CommunityHealth.Repo.get!(CommunityHealth.Reports.Report, report.id).status ==
               "resolved"
    end

    test "dismisses the report on a no_violation decision", %{
      community: community,
      report: report,
      moderation_case: moderation_case
    } do
      {:ok, _decision} =
        Moderation.decide_case(community, moderation_case.id, %{
          reviewer_external_id: "guardian-1",
          decision: "no_violation"
        })

      assert CommunityHealth.Repo.get!(CommunityHealth.Reports.Report, report.id).status ==
               "dismissed"
    end

    test "rejects a decision from someone other than the assigned reviewer", %{
      community: community,
      moderation_case: moderation_case
    } do
      assert {:error, :not_assigned_reviewer} =
               Moderation.decide_case(community, moderation_case.id, %{
                 reviewer_external_id: "someone-else",
                 decision: "violation"
               })
    end

    test "rejects a second decision on an already-decided case", %{
      community: community,
      moderation_case: moderation_case
    } do
      {:ok, _} =
        Moderation.decide_case(community, moderation_case.id, %{
          reviewer_external_id: "guardian-1",
          decision: "unclear"
        })

      assert {:error, :already_decided} =
               Moderation.decide_case(community, moderation_case.id, %{
                 reviewer_external_id: "guardian-1",
                 decision: "violation"
               })
    end

    test "404s (via :not_found) for a case that doesn't exist", %{community: community} do
      assert {:error, :not_found} =
               Moderation.decide_case(community, -1, %{
                 reviewer_external_id: "guardian-1",
                 decision: "violation"
               })
    end
  end

  describe "create_action/3" do
    setup %{platform: platform, community: community} do
      make_guardian(community, "guardian-1")
      author_post(platform, community, "author-1", "post-1")
      report = report!(platform, community, "reporter-1", "post-1", "PERSONAL_ATTACK")
      moderation_case = Moderation.get_case_for_report(community, report.id)
      :ok = Moderation.assign_case_reviewer(moderation_case.id)

      {:ok, decision} =
        Moderation.decide_case(community, moderation_case.id, %{
          reviewer_external_id: "guardian-1",
          decision: "violation",
          notes: "Personal attack confirmed."
        })

      %{decision: decision}
    end

    test "records a content-only action without needing a target actor", %{
      community: community,
      decision: decision
    } do
      assert {:ok, action} =
               Moderation.create_action(community, decision.id, %{
                 action_type: "content_removed",
                 reason: "Removed for personally attacking another reader."
               })

      assert action.target_actor_external_id == "author-1"
      assert action.action_type == "content_removed"
    end

    test "records a user-targeted action, deriving the target from the case", %{
      community: community,
      decision: decision
    } do
      assert {:ok, action} =
               Moderation.create_action(community, decision.id, %{
                 action_type: "warning",
                 reason: "First offense; a warning is proportionate."
               })

      assert action.target_actor_external_id == "author-1"
    end

    test "rejects a user-targeted action type when the target actor is unknown", %{
      platform: platform,
      community: community
    } do
      report = report!(platform, community, "reporter-2", "post-never-seen", "PERSONAL_ATTACK")
      moderation_case = Moderation.get_case_for_report(community, report.id)
      :ok = Moderation.assign_case_reviewer(moderation_case.id)

      {:ok, decision} =
        Moderation.decide_case(community, moderation_case.id, %{
          reviewer_external_id: "guardian-1",
          decision: "violation"
        })

      assert {:error, changeset} =
               Moderation.create_action(community, decision.id, %{
                 action_type: "warning",
                 reason: "..."
               })

      assert "is required for warning actions, but CH could not derive the reported content's author" in errors_on(
               changeset,
               :target_actor_external_id
             )
    end

    test "rejects an action on a no_violation decision", %{
      platform: platform,
      community: community
    } do
      author_post(platform, community, "author-2", "post-2")
      report = report!(platform, community, "reporter-2", "post-2", "PERSONAL_ATTACK")
      moderation_case = Moderation.get_case_for_report(community, report.id)
      :ok = Moderation.assign_case_reviewer(moderation_case.id)

      {:ok, decision} =
        Moderation.decide_case(community, moderation_case.id, %{
          reviewer_external_id: "guardian-1",
          decision: "no_violation"
        })

      assert {:error, :no_violation_to_act_on} =
               Moderation.create_action(community, decision.id, %{
                 action_type: "warning",
                 reason: "..."
               })
    end
  end

  describe "file_appeal/3 and assign_appeal_reviewer/1" do
    setup %{platform: platform, community: community} do
      make_guardian(community, "guardian-1")
      make_guardian(community, "guardian-2")
      author_post(platform, community, "author-1", "post-1")
      report = report!(platform, community, "reporter-1", "post-1", "PERSONAL_ATTACK")
      moderation_case = Moderation.get_case_for_report(community, report.id)
      :ok = Moderation.assign_case_reviewer(moderation_case.id)
      original_reviewer = Moderation.get_case(community, moderation_case.id).reviewer_external_id

      {:ok, decision} =
        Moderation.decide_case(community, moderation_case.id, %{
          reviewer_external_id: original_reviewer,
          decision: "violation"
        })

      {:ok, action} =
        Moderation.create_action(community, decision.id, %{action_type: "warning", reason: "..."})

      %{action: action, original_reviewer: original_reviewer}
    end

    test "the target actor can appeal, and assignment skips the original reviewer", %{
      community: community,
      action: action,
      original_reviewer: original_reviewer
    } do
      assert {:ok, appeal} =
               Moderation.file_appeal(community, action.id, %{
                 appellant_external_id: "author-1",
                 reason: "I was discussing the interpretation, not the person."
               })

      assert_enqueued(worker: AppealAssignmentWorker, args: %{appeal_id: appeal.id})
      :ok = Moderation.assign_appeal_reviewer(appeal.id)

      reassigned = Moderation.get_appeal(community, appeal.id)
      assert reassigned.reviewed_by != nil
      assert reassigned.reviewed_by != original_reviewer
    end

    test "rejects an appeal from someone other than the action's target", %{
      community: community,
      action: action
    } do
      assert {:error, :not_the_target_actor} =
               Moderation.file_appeal(community, action.id, %{
                 appellant_external_id: "someone-else",
                 reason: "..."
               })
    end

    test "is idempotent on the action", %{community: community, action: action} do
      attrs = %{appellant_external_id: "author-1", reason: "First reason"}
      {:ok, first} = Moderation.file_appeal(community, action.id, attrs)

      {:ok, second} =
        Moderation.file_appeal(community, action.id, %{attrs | reason: "Different reason"})

      assert first.id == second.id
      assert second.reason == "First reason"
    end
  end

  describe "resolve_appeal/3 and count_confirmed_violations/2" do
    setup %{platform: platform, community: community} do
      make_guardian(community, "guardian-1")
      make_guardian(community, "guardian-2")
      author_post(platform, community, "author-1", "post-1")
      report = report!(platform, community, "reporter-1", "post-1", "PERSONAL_ATTACK")
      moderation_case = Moderation.get_case_for_report(community, report.id)
      :ok = Moderation.assign_case_reviewer(moderation_case.id)
      original_reviewer = Moderation.get_case(community, moderation_case.id).reviewer_external_id

      {:ok, decision} =
        Moderation.decide_case(community, moderation_case.id, %{
          reviewer_external_id: original_reviewer,
          decision: "violation"
        })

      {:ok, action} =
        Moderation.create_action(community, decision.id, %{action_type: "warning", reason: "..."})

      {:ok, appeal} =
        Moderation.file_appeal(community, action.id, %{
          appellant_external_id: "author-1",
          reason: "..."
        })

      :ok = Moderation.assign_appeal_reviewer(appeal.id)
      appeal = Moderation.get_appeal(community, appeal.id)

      %{appeal: appeal}
    end

    test "counts a violation as confirmed until an appeal upholds it", %{
      community: community,
      appeal: appeal
    } do
      assert Moderation.count_confirmed_violations(community, "author-1") == 1

      {:ok, resolved} =
        Moderation.resolve_appeal(community, appeal.id, %{
          reviewer_external_id: appeal.reviewed_by,
          status: "upheld"
        })

      assert resolved.status == "upheld"
      assert Moderation.count_confirmed_violations(community, "author-1") == 0
    end

    test "a denied appeal leaves the violation confirmed", %{community: community, appeal: appeal} do
      {:ok, _resolved} =
        Moderation.resolve_appeal(community, appeal.id, %{
          reviewer_external_id: appeal.reviewed_by,
          status: "denied"
        })

      assert Moderation.count_confirmed_violations(community, "author-1") == 1
    end

    test "rejects resolution from someone other than the assigned reviewer", %{
      community: community,
      appeal: appeal
    } do
      assert {:error, :not_assigned_reviewer} =
               Moderation.resolve_appeal(community, appeal.id, %{
                 reviewer_external_id: "someone-else",
                 status: "upheld"
               })
    end

    test "rejects resolving the same appeal twice", %{community: community, appeal: appeal} do
      {:ok, _} =
        Moderation.resolve_appeal(community, appeal.id, %{
          reviewer_external_id: appeal.reviewed_by,
          status: "denied"
        })

      assert {:error, :already_resolved} =
               Moderation.resolve_appeal(community, appeal.id, %{
                 reviewer_external_id: appeal.reviewed_by,
                 status: "upheld"
               })
    end
  end

  defp errors_on(changeset, field) do
    changeset.errors
    |> Keyword.get_values(field)
    |> Enum.map(fn {msg, _opts} -> msg end)
  end
end
