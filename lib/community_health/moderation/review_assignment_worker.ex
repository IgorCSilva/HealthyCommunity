defmodule CommunityHealth.Moderation.ReviewAssignmentWorker do
  @moduledoc """
  CH-Step 6: assigns a moderation case to an eligible reviewer, excluding
  conflicts of interest (mvp_structure.md §23), off the request path —
  enqueued by `CommunityHealth.Reports.submit_report/3` right after a
  fresh (non-replayed) report opens a case.
  """

  use Oban.Worker, queue: :moderation, max_attempts: 5

  alias CommunityHealth.Moderation

  def enqueue(moderation_case_id) do
    %{"moderation_case_id" => moderation_case_id} |> new() |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"moderation_case_id" => moderation_case_id}}) do
    Moderation.assign_case_reviewer(moderation_case_id)
  end
end
