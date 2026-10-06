defmodule CommunityHealth.Roles do
  @moduledoc """
  CH-Step 9: roles and permissions are a small, fixed, global taxonomy
  (mvp_structure.md §11-12), not per-community config — authority comes
  from a role's `role_permissions`, never from reputation directly
  (decoupled_healthy_system.md §17: "I have 10,000 points, therefore I can
  punish other users" is exactly what this separation prevents).

  Also exposes Guardian eligibility **read-only**
  (mvp_structure.md §18, decoupled_healthy_system.md §16-17): a consumer
  can show a member their progress toward a role without that role being
  grantable through this API — promotion is still an operator action via
  `mix community_health.set_role`.
  """

  import Ecto.Query

  alias CommunityHealth.Communities
  alias CommunityHealth.Communities.Community
  alias CommunityHealth.Repo
  alias CommunityHealth.Reputation
  alias CommunityHealth.Roles.{Permission, Role, RolePermission}

  @doc "All roles, ordered by code."
  def list_roles, do: Repo.all(from r in Role, order_by: r.code)

  @doc "Looks up a role by its code, or nil."
  def get_role_by_code(code), do: Repo.one(from r in Role, where: r.code == ^code)

  @doc "The permission codes granted to a role, via role_permissions."
  def permissions_for(%Role{id: role_id}) do
    Repo.all(
      from p in Permission,
        join: rp in RolePermission,
        on: rp.permission_id == p.id,
        where: rp.role_id == ^role_id,
        order_by: p.code,
        select: p.code
    )
  end

  @doc "True when `role` grants `permission_code`."
  def has_permission?(%Role{} = role, permission_code) do
    permission_code in permissions_for(role)
  end

  @doc """
  Assigns `role_code` to an actor within `community`. The actor must
  already be a member (see `CommunityHealth.Communities.ensure_member/2`).
  """
  def set_role(%Community{} = community, actor_external_id, role_code) do
    case {Communities.get_member(community, actor_external_id), get_role_by_code(role_code)} do
      {nil, _role} -> {:error, :actor_not_found}
      {_membership, nil} -> {:error, :role_not_found}
      {membership, role} -> membership |> Ecto.Changeset.change(role_id: role.id) |> Repo.update()
    end
  end

  @doc "The role code currently held by an actor in `community`, or nil."
  def role_code_for(%Community{} = community, actor_external_id) do
    case Communities.get_member(community, actor_external_id) do
      nil -> nil
      %{role_id: nil} -> nil
      membership -> Repo.one(from r in Role, where: r.id == ^membership.role_id, select: r.code)
    end
  end

  @guardian_requirements [
    %{code: "account_age_days", label: "Account age (days)", threshold: 30},
    %{code: "reputation_score", label: "Reputation score", threshold: 250},
    %{code: "confirmed_violations", label: "Confirmed violations (max allowed)", threshold: 1},
    %{code: "constructive_contributions", label: "Constructive contributions (min)", threshold: 10}
  ]

  @doc """
  Guardian-candidate eligibility (mvp_structure.md §18), returning each
  requirement, its threshold, and the actor's current value — not just a
  boolean — so a consumer can show a member their own progress. Only
  `"guardian"` has defined criteria today; any other role_code is
  unsupported.
  """
  def role_progress(%Community{} = community, actor_external_id, "guardian") do
    case Communities.get_member(community, actor_external_id) do
      nil ->
        {:error, :actor_not_found}

      membership ->
        current = %{
          "account_age_days" => account_age_days(membership),
          "reputation_score" => Reputation.get_score(community, actor_external_id).score,
          # No moderation-review system exists yet (CH-Step 6/7 are "Not
          # started"), so this is always 0 for now — the column this would
          # read from doesn't exist until that step ships.
          "confirmed_violations" => 0,
          "constructive_contributions" => Reputation.count_positive_events(community, actor_external_id)
        }

        requirements =
          Enum.map(@guardian_requirements, fn %{code: code, threshold: threshold} = req ->
            value = Map.fetch!(current, code)
            Map.merge(req, %{current: value, met: meets?(code, value, threshold)})
          end)

        {:ok, %{role_code: "guardian", eligible: Enum.all?(requirements, & &1.met), requirements: requirements}}
    end
  end

  def role_progress(_community, _actor_external_id, _role_code), do: {:error, :unsupported_role}

  defp meets?("confirmed_violations", value, threshold), do: value <= threshold
  defp meets?(_code, value, threshold), do: value >= threshold

  defp account_age_days(membership) do
    NaiveDateTime.diff(NaiveDateTime.utc_now(), membership.inserted_at, :day)
  end
end
