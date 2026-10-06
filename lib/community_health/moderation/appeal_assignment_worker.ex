defmodule CommunityHealth.Moderation.AppealAssignmentWorker do
  @moduledoc """
  CH-Step 7: assigns an appeal to a reviewer, reusing CH-Step 6's
  conflict-of-interest exclusions plus one more — the original decision's
  reviewer is always excluded (mvp_structure.md §25: "Don't send the
  appeal to the same person who made the original decision").
  """

  use Oban.Worker, queue: :moderation, max_attempts: 5

  alias CommunityHealth.Moderation

  def enqueue(appeal_id) do
    %{"appeal_id" => appeal_id} |> new() |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appeal_id" => appeal_id}}) do
    Moderation.assign_appeal_reviewer(appeal_id)
  end
end
