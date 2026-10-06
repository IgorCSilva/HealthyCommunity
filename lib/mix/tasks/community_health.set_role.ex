defmodule Mix.Tasks.CommunityHealth.SetRole do
  use Mix.Task

  alias CommunityHealth.Communities
  alias CommunityHealth.Platforms
  alias CommunityHealth.Roles

  @shortdoc "Assigns a role (reader/contributor/guardian/moderator/admin) to a member"

  @moduledoc """
  Usage:

      mix community_health.set_role PLATFORM_CODE COMMUNITY_REF ACTOR_REF ROLE_CODE

  Example:

      mix community_health.set_role underlined default user-42 guardian

  There's deliberately no public write endpoint for this — CH-Step 9 only
  exposes role-progress read-only; promotion stays an operator action here,
  same as `mix community_health.add_rule`.
  """

  def run([platform_code, community_ref, actor_ref, role_code]) do
    Mix.Task.run("app.start")

    with {:ok, platform} <- find_platform(platform_code),
         {:ok, community} <- find_community(platform, community_ref),
         {:ok, _membership} <- Roles.set_role(community, actor_ref, role_code) do
      Mix.shell().info("#{actor_ref} is now #{role_code} in community #{community_ref}.")
    else
      {:error, :platform_not_found} ->
        Mix.shell().error("Platform #{platform_code} not found.")

      {:error, :community_not_found} ->
        Mix.shell().error("Community #{community_ref} not found for platform #{platform_code}.")

      {:error, :actor_not_found} ->
        Mix.shell().error("#{actor_ref} is not a member of community #{community_ref}.")

      {:error, :role_not_found} ->
        Mix.shell().error("Role #{role_code} does not exist.")
    end
  end

  def run(_args) do
    Mix.shell().error("Usage: mix community_health.set_role PLATFORM_CODE COMMUNITY_REF ACTOR_REF ROLE_CODE")
  end

  defp find_platform(code) do
    case Platforms.get_by_code(code) do
      nil -> {:error, :platform_not_found}
      platform -> {:ok, platform}
    end
  end

  defp find_community(platform, community_ref) do
    case Communities.get_community(platform, community_ref) do
      nil -> {:error, :community_not_found}
      community -> {:ok, community}
    end
  end
end
