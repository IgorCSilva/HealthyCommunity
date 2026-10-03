defmodule CommunityHealth.Communities do
  @moduledoc """
  CH-Step 2: communities and membership, scoped per platform.

  A community always belongs to the platform that registered it
  (`decoupled_healthy_system.md §3-4`); nothing here is ever shared
  across platforms. Both operations are idempotent so a caller can
  safely retry without checking "does this already exist" first.
  """

  import Ecto.Query

  alias CommunityHealth.Repo
  alias CommunityHealth.Platforms.Platform
  alias CommunityHealth.Communities.{Community, Membership}

  @doc "Idempotently registers a community under a platform."
  def ensure_community(%Platform{id: platform_id}, external_ref, name) do
    %Community{}
    |> Community.changeset(%{platform_id: platform_id, external_ref: external_ref, name: name})
    |> Repo.insert(
      on_conflict: {:replace, [:name, :updated_at]},
      conflict_target: [:platform_id, :external_ref],
      returning: true
    )
  end

  @doc "Looks up a platform's community by its external reference, or nil."
  def get_community(%Platform{id: platform_id}, external_ref) do
    Repo.one(
      from c in Community,
        where: c.platform_id == ^platform_id and c.external_ref == ^external_ref
    )
  end

  @doc "Idempotently ensures an actor is a member of a community."
  def ensure_member(%Community{id: community_id}, actor_external_id) do
    %Membership{}
    |> Membership.changeset(%{community_id: community_id, actor_external_id: actor_external_id})
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:community_id, :actor_external_id],
      returning: true
    )
    |> case do
      {:ok, %Membership{id: nil}} ->
        {:ok,
         Repo.one!(
           from m in Membership,
             where:
               m.community_id == ^community_id and m.actor_external_id == ^actor_external_id
         )}

      {:ok, membership} ->
        {:ok, membership}
    end
  end
end
