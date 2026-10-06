defmodule CommunityHealth.Moderation do
  @moduledoc """
  CH-Step 6 (Moderation Review & Decisions) and CH-Step 7 (Moderation
  Actions & Appeals): a report (CH-Step 5) opens a case, a case gets an
  auditable decision — violation, no_violation, or unclear
  (mvp_structure.md §9) — a confirmed violation can carry a proportionate
  action (§10), and the targeted actor can appeal that action to a
  reviewer other than the one who decided it (§25).

  Decision separate from action: changing the punishment policy later
  never means revisiting past decisions (§10's "this separation will save
  you headaches later").

  Reviewer assignment (for both a fresh case and an appeal) excludes
  three conflicts of interest (§23): the reporter/appellant themselves,
  the reported actor's own content, and anyone who's had a "recent
  dispute" with the reported actor — defined here as having reported each
  other's content within the last 30 days. Severity routes the case to a
  Guardian (`review_reports` permission) for low/medium, or straight to a
  Moderator (`remove_content` permission) for high/critical, per §19's
  severity classifier; the severity is `community_rules.severity`, copied
  onto the case at filing time.

  CH's resources (CH-Step 3) have no owner column by design
  (decoupled_healthy_system.md §13) — `reported_actor_external_id` is
  derived, once, from the earliest `community_actions` row recorded
  against the reported resource (its creation event, whatever action_type
  that happened to be). This can come back `nil` for a resource CH never
  saw an action for; content-only action types (content_removed/
  content_hidden/comment_locked) still work without one, but user-level
  ones (warning/temporary_suspension/permanent_ban) require it.
  """

  import Ecto.Query

  alias CommunityHealth.Actions.CommunityAction
  alias CommunityHealth.Communities.Membership
  alias CommunityHealth.Communities.Community

  alias CommunityHealth.Moderation.{
    AppealAssignmentWorker,
    ModerationAction,
    ModerationAppeal,
    ModerationCase,
    ModerationDecision,
    ReviewAssignmentWorker
  }

  alias CommunityHealth.Reports.Report
  alias CommunityHealth.Repo
  alias CommunityHealth.Roles.{Permission, Role, RolePermission}
  alias CommunityHealth.Rules

  @review_permission "review_reports"
  @escalated_permission "remove_content"
  @escalated_severities ~w(high critical)
  @dispute_window_days 30

  # --- Cases -------------------------------------------------------------

  @doc """
  Idempotently opens a case for a freshly-filed report and enqueues
  reviewer assignment. A no-op (returns the existing case) if called
  again for the same report.
  """
  def open_case_for_report(%Community{} = community, %Report{} = report) do
    severity =
      case Rules.get_active_rule(community, report.reason) do
        nil -> "medium"
        rule -> rule.severity
      end

    %ModerationCase{}
    |> ModerationCase.changeset(%{
      report_id: report.id,
      community_id: community.id,
      reported_actor_external_id: original_actor_for_resource(report.resource_id),
      severity: severity
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:report_id], returning: true)
    |> after_case_insert()
  end

  defp after_case_insert({:ok, %ModerationCase{id: nil, report_id: report_id}}) do
    {:ok, Repo.one!(from(c in ModerationCase, where: c.report_id == ^report_id))}
  end

  defp after_case_insert({:ok, moderation_case}) do
    ReviewAssignmentWorker.enqueue(moderation_case.id)
    {:ok, moderation_case}
  end

  defp after_case_insert({:error, changeset}), do: {:error, changeset}

  @doc "Looks up a case by CH id, scoped to `community`, or nil."
  def get_case(%Community{id: community_id}, case_id) do
    Repo.one(
      from c in ModerationCase, where: c.id == ^case_id and c.community_id == ^community_id
    )
  end

  @doc "Looks up the case opened for `report`, or nil if assignment hasn't run yet."
  def get_case_for_report(%Community{id: community_id}, report_id) do
    Repo.one(
      from c in ModerationCase,
        where: c.report_id == ^report_id and c.community_id == ^community_id
    )
  end

  @doc """
  Assigns an eligible reviewer to a still-`"pending"` case. Called by
  `ReviewAssignmentWorker`. A no-op when the case is already
  assigned/decided (replay-safe) or when no eligible reviewer exists yet
  (the case stays `"pending"` for a later retry).
  """
  def assign_case_reviewer(case_id) do
    case Repo.get(ModerationCase, case_id) do
      nil ->
        :ok

      %ModerationCase{status: "pending"} = moderation_case ->
        report = Repo.get!(Report, moderation_case.report_id)

        exclude =
          [report.reporter_external_id, moderation_case.reported_actor_external_id] ++
            disputed_partners(
              moderation_case.community_id,
              moderation_case.reported_actor_external_id
            )

        candidates =
          eligible_reviewers(moderation_case.community_id, moderation_case.severity, exclude)

        case pick_reviewer(candidates, moderation_case.community_id) do
          nil ->
            :ok

          reviewer ->
            moderation_case
            |> Ecto.Changeset.change(reviewer_external_id: reviewer, status: "assigned")
            |> Repo.update()
            |> as_ok()
        end

      %ModerationCase{} ->
        :ok
    end
  end

  # --- Decisions -----------------------------------------------------------

  @doc """
  Records the assigned reviewer's decision on a case, closing it and
  updating the underlying report's status (`"dismissed"` for
  `no_violation`, `"resolved"` for `violation`/`unclear` — something was
  concluded either way).
  """
  def decide_case(
        %Community{} = community,
        case_id,
        %{reviewer_external_id: reviewer_external_id} = attrs
      ) do
    case get_case(community, case_id) do
      nil ->
        {:error, :not_found}

      %ModerationCase{status: "decided"} ->
        {:error, :already_decided}

      %ModerationCase{reviewer_external_id: assigned} when assigned != reviewer_external_id ->
        {:error, :not_assigned_reviewer}

      moderation_case ->
        Repo.transaction(fn ->
          with {:ok, decision} <-
                 %ModerationDecision{}
                 |> ModerationDecision.changeset(
                   Map.put(attrs, :moderation_case_id, moderation_case.id)
                 )
                 |> Repo.insert(),
               {:ok, _case} <-
                 moderation_case |> Ecto.Changeset.change(status: "decided") |> Repo.update(),
               {:ok, _report} <-
                 update_report_status(moderation_case.report_id, decision.decision) do
            decision
          else
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)
    end
  end

  defp update_report_status(report_id, "no_violation") do
    Repo.get!(Report, report_id) |> Ecto.Changeset.change(status: "dismissed") |> Repo.update()
  end

  defp update_report_status(report_id, _decision) do
    Repo.get!(Report, report_id) |> Ecto.Changeset.change(status: "resolved") |> Repo.update()
  end

  @doc "Looks up a decision by CH id, scoped to `community`, or nil."
  def get_decision(%Community{id: community_id}, decision_id) do
    Repo.one(
      from d in ModerationDecision,
        join: c in ModerationCase,
        on: c.id == d.moderation_case_id,
        where: d.id == ^decision_id and c.community_id == ^community_id
    )
  end

  # --- Actions ---------------------------------------------------------------

  @doc """
  Records a proportionate action against a decided case — only a
  `"violation"` decision can carry one. `target_actor_external_id` is
  derived from the case, not accepted as input, so a caller can't point
  an action at an arbitrary actor.
  """
  def create_action(%Community{} = community, decision_id, attrs) do
    case get_decision(community, decision_id) do
      nil ->
        {:error, :not_found}

      %ModerationDecision{decision: "violation"} = decision ->
        target = target_actor_for_decision(decision)

        %ModerationAction{}
        |> ModerationAction.changeset(
          Map.merge(attrs, %{
            moderation_decision_id: decision.id,
            target_actor_external_id: target
          })
        )
        |> Repo.insert()

      %ModerationDecision{} ->
        {:error, :no_violation_to_act_on}
    end
  end

  defp target_actor_for_decision(%ModerationDecision{moderation_case_id: case_id}) do
    Repo.one(
      from c in ModerationCase, where: c.id == ^case_id, select: c.reported_actor_external_id
    )
  end

  @doc "Looks up an action by CH id, scoped to `community`, or nil."
  def get_action(%Community{id: community_id}, action_id) do
    Repo.one(
      from a in ModerationAction,
        join: d in ModerationDecision,
        on: d.id == a.moderation_decision_id,
        join: c in ModerationCase,
        on: c.id == d.moderation_case_id,
        where: a.id == ^action_id and c.community_id == ^community_id
    )
  end

  # --- Appeals ---------------------------------------------------------------

  @doc """
  Files an appeal against an action — only the action's own target can
  appeal it. Idempotent on the action (a replay returns the original
  appeal); enqueues assignment to a reviewer other than the one who made
  the original decision.
  """
  def file_appeal(
        %Community{} = community,
        action_id,
        %{appellant_external_id: appellant} = attrs
      ) do
    case get_action(community, action_id) do
      nil ->
        {:error, :not_found}

      %ModerationAction{target_actor_external_id: target}
      when is_nil(target) or target != appellant ->
        {:error, :not_the_target_actor}

      action ->
        %ModerationAppeal{}
        |> ModerationAppeal.changeset(Map.put(attrs, :moderation_action_id, action.id))
        |> Repo.insert(
          on_conflict: :nothing,
          conflict_target: [:moderation_action_id],
          returning: true
        )
        |> after_appeal_insert(action.id)
    end
  end

  defp after_appeal_insert({:ok, %ModerationAppeal{id: nil}}, action_id) do
    {:ok, Repo.one!(from a in ModerationAppeal, where: a.moderation_action_id == ^action_id)}
  end

  defp after_appeal_insert({:ok, appeal}, _action_id) do
    AppealAssignmentWorker.enqueue(appeal.id)
    {:ok, appeal}
  end

  defp after_appeal_insert({:error, changeset}, _action_id), do: {:error, changeset}

  @doc "Looks up an appeal by CH id, scoped to `community`, or nil."
  def get_appeal(%Community{id: community_id}, appeal_id) do
    Repo.one(
      from ap in ModerationAppeal,
        join: a in ModerationAction,
        on: a.id == ap.moderation_action_id,
        join: d in ModerationDecision,
        on: d.id == a.moderation_decision_id,
        join: c in ModerationCase,
        on: c.id == d.moderation_case_id,
        where: ap.id == ^appeal_id and c.community_id == ^community_id
    )
  end

  @doc """
  Assigns a reviewer to a still-unassigned appeal, reusing CH-Step 6's
  conflict-of-interest exclusions plus the original decision's reviewer.
  """
  def assign_appeal_reviewer(appeal_id) do
    case Repo.get(ModerationAppeal, appeal_id) do
      nil ->
        :ok

      %ModerationAppeal{status: "pending", reviewed_by: nil} = appeal ->
        action = Repo.get!(ModerationAction, appeal.moderation_action_id)
        decision = Repo.get!(ModerationDecision, action.moderation_decision_id)
        moderation_case = Repo.get!(ModerationCase, decision.moderation_case_id)

        exclude =
          [
            appeal.appellant_external_id,
            decision.reviewer_external_id,
            moderation_case.reported_actor_external_id
          ] ++
            disputed_partners(
              moderation_case.community_id,
              moderation_case.reported_actor_external_id
            )

        candidates =
          eligible_reviewers(moderation_case.community_id, moderation_case.severity, exclude)

        case pick_reviewer(candidates, moderation_case.community_id) do
          nil ->
            :ok

          reviewer ->
            appeal |> Ecto.Changeset.change(reviewed_by: reviewer) |> Repo.update() |> as_ok()
        end

      %ModerationAppeal{} ->
        :ok
    end
  end

  @doc """
  Resolves an appeal — only the assigned reviewer can resolve it, and
  only while it's still `"pending"`. `status` is `"upheld"` (the action is
  overturned) or `"denied"` (it stands).
  """
  def resolve_appeal(%Community{} = community, appeal_id, %{
        reviewer_external_id: reviewer_external_id,
        status: status
      }) do
    case get_appeal(community, appeal_id) do
      nil ->
        {:error, :not_found}

      %ModerationAppeal{status: s} when s != "pending" ->
        {:error, :already_resolved}

      %ModerationAppeal{reviewed_by: nil} ->
        {:error, :not_yet_assigned}

      %ModerationAppeal{reviewed_by: assigned} when assigned != reviewer_external_id ->
        {:error, :not_assigned_reviewer}

      appeal ->
        appeal
        |> ModerationAppeal.resolve_changeset(%{status: status, resolved_at: DateTime.utc_now()})
        |> Repo.update()
    end
  end

  # --- Confirmed violations (read by CH-Step 9's Trust/Roles) --------------

  @doc """
  Counts `actor_external_id`'s confirmed violations in `community` — a
  `"violation"` decision whose resulting action(s) were never `"upheld"`
  on appeal. Read by `CommunityHealth.Trust.get_trust_level/2` and
  `CommunityHealth.Roles.role_progress/3`, replacing what was a
  hard-coded `0` before this step existed.
  """
  def count_confirmed_violations(%Community{id: community_id}, actor_external_id) do
    violation_decision_ids =
      Repo.all(
        from d in ModerationDecision,
          join: c in ModerationCase,
          on: c.id == d.moderation_case_id,
          where:
            c.community_id == ^community_id and c.reported_actor_external_id == ^actor_external_id and
              d.decision == "violation",
          select: d.id
      )

    overturned_decision_ids =
      Repo.all(
        from a in ModerationAction,
          join: ap in ModerationAppeal,
          on: ap.moderation_action_id == a.id,
          where: a.moderation_decision_id in ^violation_decision_ids and ap.status == "upheld",
          distinct: true,
          select: a.moderation_decision_id
      )
      |> MapSet.new()

    violation_decision_ids
    |> Enum.reject(&MapSet.member?(overturned_decision_ids, &1))
    |> length()
  end

  # --- Shared reviewer-assignment helpers ------------------------------------

  defp eligible_reviewers(community_id, severity, exclude) do
    permission =
      if severity in @escalated_severities, do: @escalated_permission, else: @review_permission

    exclude = Enum.reject(exclude, &is_nil/1)

    Repo.all(
      from m in Membership,
        join: r in Role,
        on: r.id == m.role_id,
        join: rp in RolePermission,
        on: rp.role_id == r.id,
        join: p in Permission,
        on: p.id == rp.permission_id,
        where:
          m.community_id == ^community_id and p.code == ^permission and
            m.actor_external_id not in ^exclude,
        order_by: [asc: m.inserted_at],
        select: m.actor_external_id
    )
  end

  defp pick_reviewer([], _community_id), do: nil

  defp pick_reviewer(candidates, community_id) do
    loads =
      Repo.all(
        from c in ModerationCase,
          where:
            c.community_id == ^community_id and c.status == "assigned" and
              c.reviewer_external_id in ^candidates,
          group_by: c.reviewer_external_id,
          select: {c.reviewer_external_id, count(c.id)}
      )
      |> Map.new()

    Enum.min_by(candidates, &Map.get(loads, &1, 0))
  end

  defp disputed_partners(_community_id, nil), do: []

  defp disputed_partners(community_id, reported_actor_external_id) do
    since = DateTime.add(DateTime.utc_now(), -@dispute_window_days * 24 * 60 * 60, :second)

    reported_them =
      Repo.all(
        from r in Report,
          join: c in ModerationCase,
          on: c.report_id == r.id,
          where:
            c.community_id == ^community_id and
              c.reported_actor_external_id == ^reported_actor_external_id and
              r.inserted_at >= ^since,
          select: r.reporter_external_id
      )

    reported_by_them_resource_ids =
      Repo.all(
        from r in Report,
          where:
            r.community_id == ^community_id and
              r.reporter_external_id == ^reported_actor_external_id and
              r.inserted_at >= ^since,
          select: r.resource_id
      )

    they_reported =
      reported_by_them_resource_ids
      |> original_actors_for_resources()
      |> Map.values()

    Enum.uniq(reported_them ++ they_reported)
  end

  defp original_actor_for_resource(resource_id) do
    Repo.one(
      from a in CommunityAction,
        where: a.resource_id == ^resource_id,
        order_by: [asc: a.inserted_at, asc: a.id],
        limit: 1,
        select: a.actor_external_id
    )
  end

  defp original_actors_for_resources([]), do: %{}

  defp original_actors_for_resources(resource_ids) do
    Repo.all(
      from a in CommunityAction,
        where: a.resource_id in ^resource_ids,
        distinct: a.resource_id,
        order_by: [asc: a.resource_id, asc: a.inserted_at, asc: a.id],
        select: {a.resource_id, a.actor_external_id}
    )
    |> Map.new()
  end

  defp as_ok({:ok, _}), do: :ok
  defp as_ok({:error, changeset}), do: {:error, changeset}
end
