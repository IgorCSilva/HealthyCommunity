defmodule Mix.Tasks.CommunityHealth.AddReputationRule do
  use Mix.Task

  alias CommunityHealth.Communities
  alias CommunityHealth.Platforms
  alias CommunityHealth.Reputation

  @shortdoc "Adds a reputation rule (action_type -> points, with an optional daily cap)"

  @moduledoc """
  Usage:

      mix community_health.add_reputation_rule PLATFORM_CODE COMMUNITY_REF ACTION_TYPE POINTS [DAILY_CAP]

  Example:

      mix community_health.add_reputation_rule underlined default CREATE 1 10
      mix community_health.add_reputation_rule underlined default COMMENT 2 20
  """

  def run([platform_code, community_ref, action_type, points]) do
    do_run(platform_code, community_ref, action_type, points, nil)
  end

  def run([platform_code, community_ref, action_type, points, daily_cap]) do
    do_run(platform_code, community_ref, action_type, points, daily_cap)
  end

  def run(_args) do
    Mix.shell().error(
      "Usage: mix community_health.add_reputation_rule PLATFORM_CODE COMMUNITY_REF ACTION_TYPE POINTS [DAILY_CAP]"
    )
  end

  defp do_run(platform_code, community_ref, action_type, points, daily_cap) do
    Mix.Task.run("app.start")

    with {:ok, platform} <- find_platform(platform_code),
         {:ok, community} <- find_community(platform, community_ref),
         {:ok, rule} <-
           Reputation.create_rule(community, %{
             action_type: action_type,
             points: String.to_integer(points),
             daily_cap: daily_cap && String.to_integer(daily_cap)
           }) do
      Mix.shell().info(
        "Reputation rule #{rule.action_type} -> #{rule.points}pts added to community #{community_ref}."
      )
    else
      {:error, :platform_not_found} ->
        Mix.shell().error("Platform #{platform_code} not found.")

      {:error, :community_not_found} ->
        Mix.shell().error("Community #{community_ref} not found for platform #{platform_code}.")

      {:error, changeset} ->
        Mix.shell().error("Failed to add reputation rule: #{inspect(changeset.errors)}")
    end
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
