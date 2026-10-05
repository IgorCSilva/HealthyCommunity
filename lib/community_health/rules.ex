defmodule CommunityHealth.Rules do
  @moduledoc """
  CH-Step 4: each community declares which rule violations it enforces,
  instead of CH hard-coding a fixed violation taxonomy
  (decoupled_healthy_system.md §8). A report (CH-Step 5) is always filed
  against one of a community's *active* rules, by code.
  """

  import Ecto.Query

  alias CommunityHealth.Communities.Community
  alias CommunityHealth.Repo
  alias CommunityHealth.Rules.CommunityRule

  @doc "Adds a rule to a community. Codes are unique per community."
  def create_rule(%Community{id: community_id}, attrs) do
    %CommunityRule{}
    |> CommunityRule.changeset(Map.put(attrs, :community_id, community_id))
    |> Repo.insert()
  end

  @doc "Lists a community's currently active rules, ordered by code."
  def list_active_rules(%Community{id: community_id}) do
    Repo.all(
      from r in CommunityRule,
        where: r.community_id == ^community_id and r.active == true,
        order_by: r.code
    )
  end

  @doc "Looks up a community's active rule by code, or nil."
  def get_active_rule(%Community{id: community_id}, code) do
    Repo.one(
      from r in CommunityRule,
        where: r.community_id == ^community_id and r.code == ^code and r.active == true
    )
  end
end
