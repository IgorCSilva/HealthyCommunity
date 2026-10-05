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
  alias CommunityHealth.Resources

  @doc """
  Records an action against a resource, registering the resource on first
  sight. `attrs` requires `:actor_external_id`, `:action_type`,
  `:resource_type`, `:resource_ref`, `:event_key`, and accepts optional
  `:context` (defaults to `%{}`) and `:occurred_at` (defaults to now).
  """
  def record_action(%Platform{id: platform_id} = platform, %Community{id: community_id}, attrs) do
    with {:ok, resource} <-
           Resources.ensure_resource(platform, attrs.resource_type, attrs.resource_ref) do
      %CommunityAction{}
      |> CommunityAction.changeset(%{
        platform_id: platform_id,
        community_id: community_id,
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
      |> fetch_if_conflicted(platform_id, attrs.event_key)
    end
  end

  defp fetch_if_conflicted({:ok, %CommunityAction{id: nil}}, platform_id, event_key) do
    {:ok,
     Repo.one!(
       from a in CommunityAction,
         where: a.platform_id == ^platform_id and a.event_key == ^event_key
     )}
  end

  defp fetch_if_conflicted({:ok, action}, _platform_id, _event_key), do: {:ok, action}
  defp fetch_if_conflicted({:error, changeset}, _platform_id, _event_key), do: {:error, changeset}
end
