defmodule CommunityHealth.Reports do
  @moduledoc """
  CH-Step 5: an actor flags a resource as violating one of its community's
  active rules — distinct from a moderation decision from the start
  (mvp_structure.md §7): nothing happens to the reported content yet, this
  only records that a report exists.

  Filing is idempotent on `[platform_id, resource_id, reporter_external_id]`
  — the same actor reporting the same resource again (e.g. an Oban retry
  replaying a submission that timed out) returns the original report
  instead of creating a duplicate.
  """

  import Ecto.Query

  alias CommunityHealth.Communities.Community
  alias CommunityHealth.Moderation
  alias CommunityHealth.Platforms.Platform
  alias CommunityHealth.Repo
  alias CommunityHealth.Reports.Report
  alias CommunityHealth.Resources

  def submit_report(
        %Platform{id: platform_id} = platform,
        %Community{id: community_id} = community,
        attrs
      ) do
    with {:ok, resource} <-
           Resources.ensure_resource(platform, attrs.resource_type, attrs.resource_ref) do
      %Report{}
      |> Report.changeset(%{
        platform_id: platform_id,
        community_id: community_id,
        resource_id: resource.id,
        reporter_external_id: attrs.reporter_external_id,
        reason: attrs.reason,
        description: Map.get(attrs, :description)
      })
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:platform_id, :resource_id, :reporter_external_id],
        returning: true
      )
      |> after_insert(community, platform_id, resource.id, attrs.reporter_external_id)
    end
  end

  defp after_insert(
         {:ok, %Report{id: nil}},
         _community,
         platform_id,
         resource_id,
         reporter_external_id
       ) do
    {:ok,
     Repo.one!(
       from r in Report,
         where:
           r.platform_id == ^platform_id and r.resource_id == ^resource_id and
             r.reporter_external_id == ^reporter_external_id
     )}
  end

  defp after_insert({:ok, report}, community, _platform_id, _resource_id, _reporter_external_id) do
    # CH-Step 6: every genuinely new report opens a moderation case —
    # fire-and-forget, same as Actions.record_action/3's reputation
    # side-effect, so a case-opening hiccup never blocks report filing.
    Moderation.open_case_for_report(community, report)
    {:ok, report}
  end

  defp after_insert(
         {:error, changeset},
         _community,
         _platform_id,
         _resource_id,
         _reporter_external_id
       ),
       do: {:error, changeset}
end
