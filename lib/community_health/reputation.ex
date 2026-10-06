defmodule CommunityHealth.Reputation do
  @moduledoc """
  CH-Step 8: reputation is generated from generic actions, never
  hard-coded per book-app feature (decoupled_healthy_system.md §9) —
  a community declares `reputation_rules` mapping `action_type -> points`,
  and every fresh `community_actions` row (CH-Step 3) is checked against
  them here, from `CommunityHealth.Actions.record_action/3`.

  Diminishing returns are enforced as a daily cap per `(actor, action_type)`
  (the "Or simply use daily caps" option from mvp_structure.md §16, chosen
  over tiered per-action reduction): a rule's cap is applied at the moment
  an event is recorded, so a rule changed or deactivated later never
  rewrites the point value of reputation already earned under it.

  `reputation_scores` is a cached rollup — a plain `SUM(points)` over
  `reputation_events` for an actor — recomputed by `ReputationRollupWorker`
  off the request path so awarding reputation never blocks the ingestion
  request that triggered it.
  """

  import Ecto.Query

  alias CommunityHealth.Actions.CommunityAction
  alias CommunityHealth.Communities.Community
  alias CommunityHealth.Repo
  alias CommunityHealth.Reputation.{ReputationEvent, ReputationRollupWorker, ReputationRule, ReputationScore}

  @doc "Adds a reputation rule to a community. One rule per action_type per community."
  def create_rule(%Community{id: community_id}, attrs) do
    %ReputationRule{}
    |> ReputationRule.changeset(Map.put(attrs, :community_id, community_id))
    |> Repo.insert()
  end

  @doc "Looks up a community's active reputation rule for an action_type, or nil."
  def get_active_rule(%Community{id: community_id}, action_type) do
    get_active_rule_by_ids(community_id, action_type)
  end

  defp get_active_rule_by_ids(community_id, action_type) do
    Repo.one(
      from r in ReputationRule,
        where: r.community_id == ^community_id and r.action_type == ^action_type and r.active == true
    )
  end

  @doc """
  Checks `action` (a freshly-inserted `CommunityAction`, never a replayed
  one) against `community`'s active reputation rules and records a
  `ReputationEvent` if one matches. A no-op when no rule matches this
  action_type. Enqueues the rollup worker for the actor on success.
  """
  def record_event_for_action(%Community{id: community_id} = community, %CommunityAction{} = action) do
    case get_active_rule_by_ids(community_id, action.action_type) do
      nil ->
        :ok

      rule ->
        points = capped_points(community_id, action.actor_external_id, rule, action.occurred_at)

        %ReputationEvent{}
        |> ReputationEvent.changeset(%{
          community_id: community_id,
          actor_external_id: action.actor_external_id,
          action_type: action.action_type,
          points: points,
          community_action_id: action.id,
          occurred_at: action.occurred_at
        })
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:community_action_id], returning: true)
        |> after_event_insert(community, action.actor_external_id)
    end
  end

  defp after_event_insert({:ok, %ReputationEvent{id: nil}}, _community, _actor_external_id), do: :ok

  defp after_event_insert({:ok, _event}, %Community{id: community_id}, actor_external_id) do
    ReputationRollupWorker.enqueue(community_id, actor_external_id)
    :ok
  end

  defp after_event_insert({:error, changeset}, _community, _actor_external_id), do: {:error, changeset}

  # Penalties (negative-point rules, e.g. a future CONFIRMED_VIOLATION) are
  # never capped — a daily cap exists to stop farming positive reputation,
  # not to protect a bad actor from the full weight of a penalty.
  defp capped_points(_community_id, _actor_external_id, %ReputationRule{points: points}, _occurred_at)
       when points <= 0,
       do: points

  defp capped_points(_community_id, _actor_external_id, %ReputationRule{points: points, daily_cap: nil}, _occurred_at),
    do: points

  defp capped_points(
         community_id,
         actor_external_id,
         %ReputationRule{points: points, action_type: action_type, daily_cap: cap},
         occurred_at
       ) do
    already = points_awarded_today(community_id, actor_external_id, action_type, occurred_at)
    max(min(points, cap - already), 0)
  end

  defp points_awarded_today(community_id, actor_external_id, action_type, occurred_at) do
    day_start = DateTime.new!(DateTime.to_date(occurred_at), ~T[00:00:00], "Etc/UTC")
    day_end = DateTime.add(day_start, 1, :day)

    Repo.one(
      from re in ReputationEvent,
        where:
          re.community_id == ^community_id and re.actor_external_id == ^actor_external_id and
            re.action_type == ^action_type and re.occurred_at >= ^day_start and re.occurred_at < ^day_end,
        select: coalesce(sum(re.points), 0)
    )
  end

  @doc "Recomputes and upserts an actor's cached reputation_scores row from reputation_events."
  def rollup_score(community_id, actor_external_id) do
    total =
      Repo.one(
        from re in ReputationEvent,
          where: re.community_id == ^community_id and re.actor_external_id == ^actor_external_id,
          select: coalesce(sum(re.points), 0)
      )

    %ReputationScore{}
    |> ReputationScore.changeset(%{community_id: community_id, actor_external_id: actor_external_id, score: total})
    |> Repo.insert(
      on_conflict: {:replace, [:score, :updated_at]},
      conflict_target: [:community_id, :actor_external_id]
    )
  end

  @doc """
  Reads an actor's cached score (0 if never computed). `level` buckets the
  raw score into five tiers for display — a seedling scale, never the raw
  number, per to_be_implemented.md §12 ("Maria — 🌱🌱🌱🌱🌱" instead of
  "Maria — 8,392 karma"). Thresholds are deliberately low early on (a first
  published post should visibly move the needle) and widen at the top.
  """
  def get_score(%Community{id: community_id}, actor_external_id) do
    score =
      case Repo.one(
             from s in ReputationScore,
               where: s.community_id == ^community_id and s.actor_external_id == ^actor_external_id,
               select: s.score
           ) do
        nil -> 0
        score -> score
      end

    %{score: score, level: level_for(score)}
  end

  @levels [{300, 5}, {150, 4}, {50, 3}, {10, 2}]
  defp level_for(score) do
    Enum.find_value(@levels, 1, fn {threshold, level} -> score >= threshold && level end)
  end

  @doc """
  Count of an actor's positive-point reputation events — the "constructive
  contributions" input to `CommunityHealth.Roles.role_progress/3`'s
  Guardian-eligibility check (mvp_structure.md §18).
  """
  def count_positive_events(%Community{id: community_id}, actor_external_id) do
    Repo.one(
      from re in ReputationEvent,
        where:
          re.community_id == ^community_id and re.actor_external_id == ^actor_external_id and
            re.points > 0,
        select: count(re.id)
    )
  end
end
