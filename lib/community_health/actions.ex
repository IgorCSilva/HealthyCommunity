defmodule CommunityHealth.Actions do
  @moduledoc """
  CH-Step 3: generic resource & action ingestion. Records "actor did X to
  resource Y" as an append-only event, idempotent on a caller-supplied
  event_key — a platform can safely retry or replay a backfill without
  double-counting (decoupled_healthy_system.md §5-7).
  """

  import Ecto.Query

  alias CommunityHealth.Actions.CommunityAction
  alias CommunityHealth.Communities.Community
  alias CommunityHealth.Platforms.Platform
  alias CommunityHealth.Repo
  alias CommunityHealth.Reputation
  alias CommunityHealth.Resources

  @doc """
  Records an action against a resource, registering the resource on first
  sight. `attrs` requires `:actor_external_id`, `:action_type`,
  `:resource_type`, `:resource_ref`, `:event_key`, and accepts optional
  `:context` (defaults to `%{}`) and `:occurred_at` (defaults to now).

  A genuinely new action (not a replay of an existing event_key) is also
  checked against CH-Step 8's reputation rules for `community` — see
  `CommunityHealth.Reputation.record_event_for_action/2`.
  """
  def record_action(%Platform{id: platform_id} = platform, %Community{} = community, attrs) do
    with {:ok, resource} <-
           Resources.ensure_resource(platform, attrs.resource_type, attrs.resource_ref) do
      %CommunityAction{}
      |> CommunityAction.changeset(%{
        platform_id: platform_id,
        community_id: community.id,
        resource_id: resource.id,
        actor_external_id: attrs.actor_external_id,
        action_type: attrs.action_type,
        event_key: attrs.event_key,
        context: Map.get(attrs, :context, %{}),
        occurred_at: Map.get(attrs, :occurred_at, DateTime.utc_now())
      })
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:platform_id, :event_key],
        returning: true
      )
      |> after_insert(community, platform_id, attrs.event_key)
    end
  end

  defp after_insert({:ok, %CommunityAction{id: nil}}, _community, platform_id, event_key) do
    {:ok,
     Repo.one!(
       from a in CommunityAction,
         where: a.platform_id == ^platform_id and a.event_key == ^event_key
     )}
  end

  defp after_insert({:ok, action}, community, _platform_id, _event_key) do
    Reputation.record_event_for_action(community, action)
    {:ok, action}
  end

  defp after_insert({:error, changeset}, _community, _platform_id, _event_key), do: {:error, changeset}
end
