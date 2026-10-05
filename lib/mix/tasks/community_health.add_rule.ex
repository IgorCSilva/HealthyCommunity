defmodule Mix.Tasks.CommunityHealth.AddRule do
  use Mix.Task

  alias CommunityHealth.Communities
  alias CommunityHealth.Platforms
  alias CommunityHealth.Rules

  @shortdoc "Adds a community rule (a reason code reports can be filed against)"

  @moduledoc """
  Usage:

      mix community_health.add_rule PLATFORM_CODE COMMUNITY_REF CODE NAME SEVERITY [DESCRIPTION]

  SEVERITY is one of: low, medium, high, critical.

  Example:

      mix community_health.add_rule underlined default PERSONAL_ATTACK "Personal attack" high \\
        "Attacks another reader rather than discussing the book."
  """

  def run([platform_code, community_ref, code, name, severity | rest]) do
    Mix.Task.run("app.start")

    description =
      case Enum.join(rest, " ") do
        "" -> nil
        text -> text
      end

    with {:ok, platform} <- find_platform(platform_code),
         {:ok, community} <- find_community(platform, community_ref),
         {:ok, rule} <-
           Rules.create_rule(community, %{
             code: code,
             name: name,
             severity: severity,
             description: description
           }) do
      Mix.shell().info("Rule #{rule.code} added to community #{community_ref}.")
    else
      {:error, :platform_not_found} ->
        Mix.shell().error("Platform #{platform_code} not found.")

      {:error, :community_not_found} ->
        Mix.shell().error("Community #{community_ref} not found for platform #{platform_code}.")

      {:error, changeset} ->
        Mix.shell().error("Failed to add rule: #{inspect(changeset.errors)}")
    end
  end

  def run(_args) do
    Mix.shell().error(
      "Usage: mix community_health.add_rule PLATFORM_CODE COMMUNITY_REF CODE NAME SEVERITY [DESCRIPTION]"
    )
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
