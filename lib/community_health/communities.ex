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
  alias CommunityHealth.Roles

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

  @doc """
  Idempotently ensures an actor is a member of a community. A fresh
  membership is assigned CH-Step 9's default "reader" role; replaying this
  for an existing member never changes their current role.
  """
  def ensure_member(%Community{id: community_id}, actor_external_id) do
    %Membership{}
    |> Membership.changeset(%{
      community_id: community_id,
      actor_external_id: actor_external_id,
      role_id: reader_role_id()
    })
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

  @doc "Looks up an actor's membership row in `community`, or nil."
  def get_member(%Community{id: community_id}, actor_external_id) do
    Repo.one(
      from m in Membership,
        where: m.community_id == ^community_id and m.actor_external_id == ^actor_external_id
    )
  end

  defp reader_role_id do
    case Roles.get_role_by_code("reader") do
      nil -> nil
      role -> role.id
    end
  end
end
