defmodule Mix.Tasks.CommunityHealth.RegisterPlatform do
  use Mix.Task

  alias CommunityHealth.Platforms

  @shortdoc "Registers a platform and prints its API key once"

  @moduledoc """
  Usage:

      mix community_health.register_platform "Underlined"

  Prints the plaintext API key exactly once — only its hash is stored, so
  there is no way to recover it afterwards; run the task again to issue a
  new key.
  """

  def run([name]) do
    Mix.Task.run("app.start")

    case Platforms.register_platform(name) do
      {:ok, platform, token} ->
        Mix.shell().info("Platform #{inspect(platform.name)} registered (code: #{platform.code}).")
        Mix.shell().info("\nAPI key (store this now, it will not be shown again):\n\n  #{token}\n")

      {:error, changeset} ->
        Mix.shell().error("Failed to register platform: #{inspect(changeset.errors)}")
    end
  end

  def run(_args) do
    Mix.shell().error("Usage: mix community_health.register_platform \"Platform Name\"")
  end
end
