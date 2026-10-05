defmodule CommunityHealth.Resources do
  @moduledoc """
  CH-Step 3: resources are opaque to CH — just a (resource_type,
  external_ref) pair scoped to a platform. CH never learns what a "post" or
  a "book" is; it only ever sees the type string and the caller's own id for
  it (decoupled_healthy_system.md §5-7).
  """

  alias CommunityHealth.Platforms.Platform
  alias CommunityHealth.Repo
  alias CommunityHealth.Resources.Resource

  @doc "Idempotently registers a resource the first time an action references it."
  def ensure_resource(%Platform{id: platform_id}, resource_type, external_ref) do
    %Resource{}
    |> Resource.changeset(%{
      platform_id: platform_id,
      resource_type: resource_type,
      external_ref: external_ref
    })
    |> Repo.insert(
      on_conflict: {:replace, [:updated_at]},
      conflict_target: [:platform_id, :resource_type, :external_ref],
      returning: true
    )
  end
end
