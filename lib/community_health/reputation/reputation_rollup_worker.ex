defmodule CommunityHealth.Reputation.ReputationRollupWorker do
  @moduledoc """
  Recomputes one actor's cached `reputation_scores` row off the request
  path, enqueued by `CommunityHealth.Reputation.record_event_for_action/2`
  right after a new `ReputationEvent` is recorded.
  """

  use Oban.Worker, queue: :reputation, max_attempts: 5

  alias CommunityHealth.Reputation

  def enqueue(community_id, actor_external_id) do
    %{"community_id" => community_id, "actor_external_id" => actor_external_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"community_id" => community_id, "actor_external_id" => actor_external_id}}) do
    case Reputation.rollup_score(community_id, actor_external_id) do
      {:ok, _score} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
