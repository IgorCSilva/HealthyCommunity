defmodule CommunityHealthWeb.ModerationController do
  use CommunityHealthWeb, :controller

  alias CommunityHealth.Communities
  alias CommunityHealth.Moderation

  def show_case(conn, %{"community_ref" => community_ref, "report_id" => report_id}) do
    with_community(conn, community_ref, fn community ->
      case Moderation.get_case_for_report(community, report_id) do
        nil -> not_found(conn, "No case has been opened for this report yet")
        moderation_case -> json(conn, case_json(moderation_case))
      end
    end)
  end

  def create_decision(conn, %{"community_ref" => community_ref, "case_id" => case_id} = params) do
    with_community(conn, community_ref, fn community ->
      attrs = %{
        reviewer_external_id: params["reviewer_external_id"],
        decision: params["decision"],
        rule_id: params["rule_id"],
        notes: params["notes"]
      }

      case Moderation.decide_case(community, case_id, attrs) do
        {:ok, decision} ->
          json(conn, decision_json(decision))

        {:error, :not_found} ->
          not_found(conn, "Case not found")

        {:error, :already_decided} ->
          unprocessable(conn, "This case already has a decision")

        {:error, :not_assigned_reviewer} ->
          forbidden(conn, "Only the assigned reviewer can decide this case")

        {:error, changeset} ->
          unprocessable_changeset(conn, changeset)
      end
    end)
  end

  def create_action(
        conn,
        %{"community_ref" => community_ref, "decision_id" => decision_id} = params
      ) do
    with_community(conn, community_ref, fn community ->
      attrs = %{
        action_type: params["action_type"],
        duration_days: params["duration_days"],
        reason: params["reason"]
      }

      case Moderation.create_action(community, decision_id, attrs) do
        {:ok, action} ->
          json(conn, action_json(action))

        {:error, :not_found} ->
          not_found(conn, "Decision not found")

        {:error, :no_violation_to_act_on} ->
          unprocessable(conn, "Only a \"violation\" decision can carry a moderation action")

        {:error, changeset} ->
          unprocessable_changeset(conn, changeset)
      end
    end)
  end

  def create_appeal(conn, %{"community_ref" => community_ref, "action_id" => action_id} = params) do
    with_community(conn, community_ref, fn community ->
      attrs = %{
        appellant_external_id: params["appellant_external_id"],
        reason: params["reason"]
      }

      case Moderation.file_appeal(community, action_id, attrs) do
        {:ok, appeal} ->
          json(conn, appeal_json(appeal))

        {:error, :not_found} ->
          not_found(conn, "Action not found")

        {:error, :not_the_target_actor} ->
          forbidden(conn, "Only the actor this action was taken against can appeal it")

        {:error, changeset} ->
          unprocessable_changeset(conn, changeset)
      end
    end)
  end

  def resolve_appeal(conn, %{"community_ref" => community_ref, "appeal_id" => appeal_id} = params) do
    with_community(conn, community_ref, fn community ->
      attrs = %{reviewer_external_id: params["reviewer_external_id"], status: params["status"]}

      case Moderation.resolve_appeal(community, appeal_id, attrs) do
        {:ok, appeal} ->
          json(conn, appeal_json(appeal))

        {:error, :not_found} ->
          not_found(conn, "Appeal not found")

        {:error, :already_resolved} ->
          unprocessable(conn, "This appeal was already resolved")

        {:error, :not_yet_assigned} ->
          unprocessable(conn, "This appeal hasn't been assigned a reviewer yet")

        {:error, :not_assigned_reviewer} ->
          forbidden(conn, "Only the assigned reviewer can resolve this appeal")

        {:error, changeset} ->
          unprocessable_changeset(conn, changeset)
      end
    end)
  end

  defp with_community(conn, community_ref, fun) do
    case Communities.get_community(conn.assigns.current_platform, community_ref) do
      nil -> not_found(conn, "Community not found")
      community -> fun.(community)
    end
  end

  defp not_found(conn, detail),
    do: conn |> put_status(:not_found) |> json(%{errors: %{detail: detail}})

  defp forbidden(conn, detail),
    do: conn |> put_status(:forbidden) |> json(%{errors: %{detail: detail}})

  defp unprocessable(conn, detail),
    do: conn |> put_status(:unprocessable_entity) |> json(%{errors: %{detail: detail}})

  defp unprocessable_changeset(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)})
  end

  defp case_json(c) do
    %{
      id: c.id,
      report_id: c.report_id,
      status: c.status,
      severity: c.severity,
      reviewer_external_id: c.reviewer_external_id,
      reported_actor_external_id: c.reported_actor_external_id
    }
  end

  defp decision_json(d) do
    %{
      id: d.id,
      moderation_case_id: d.moderation_case_id,
      reviewer_external_id: d.reviewer_external_id,
      decision: d.decision,
      rule_id: d.rule_id,
      notes: d.notes
    }
  end

  defp action_json(a) do
    %{
      id: a.id,
      moderation_decision_id: a.moderation_decision_id,
      target_actor_external_id: a.target_actor_external_id,
      action_type: a.action_type,
      duration_days: a.duration_days,
      reason: a.reason
    }
  end

  defp appeal_json(ap) do
    %{
      id: ap.id,
      moderation_action_id: ap.moderation_action_id,
      appellant_external_id: ap.appellant_external_id,
      status: ap.status,
      reviewed_by: ap.reviewed_by,
      resolved_at: ap.resolved_at
    }
  end
end
