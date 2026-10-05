defmodule CommunityHealth.Platforms do
  @moduledoc """
  CH-Step 1: platform registration and API key authentication.

  A platform (e.g. "underlined") is registered once and issued an API key.
  Every request after that authenticates via that key. There is no public
  self-service registration endpoint on purpose — minting a key is how a
  caller gets to act as a platform, so it can only be done out-of-band (see
  `mix community_health.register_platform`), not over the API it would then
  use to authenticate.
  """

  import Ecto.Query

  alias CommunityHealth.Repo
  alias CommunityHealth.Platforms.{ApiKey, Platform}

  @doc """
  Registers a new platform and returns `{:ok, platform, plaintext_token}`.
  The plaintext token is only ever available at this moment — only its
  SHA-256 hash is persisted.
  """
  def register_platform(name) do
    code = unique_code_from(name)

    Repo.transaction(fn ->
      with {:ok, platform} <-
             %Platform{} |> Platform.changeset(%{name: name, code: code}) |> Repo.insert(),
           token <- generate_token(),
           {:ok, _api_key} <-
             %ApiKey{}
             |> ApiKey.changeset(%{platform_id: platform.id, token_hash: hash(token)})
             |> Repo.insert() do
        {platform, token}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, {platform, token}} -> {:ok, platform, token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Verifies a bearer token and returns `{:ok, platform}` for a live,
  unrevoked key, or `{:error, :invalid_token}` otherwise.
  """
  def authenticate(token) when is_binary(token) do
    hashed = hash(token)

    query =
      from k in ApiKey,
        join: p in Platform,
        on: p.id == k.platform_id,
        where: k.token_hash == ^hashed and is_nil(k.revoked_at),
        select: p

    case Repo.one(query) do
      nil -> {:error, :invalid_token}
      platform -> {:ok, platform}
    end
  end

  def authenticate(_), do: {:error, :invalid_token}

  @doc "Looks up a platform by its unique code, or nil."
  def get_by_code(code) do
    Repo.one(from p in Platform, where: p.code == ^code)
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  # API keys are high-entropy random tokens, not user passwords, so a fast
  # hash is the right tool here (unlike bcrypt, which exists specifically to
  # slow down guessing low-entropy human-chosen secrets).
  defp hash(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  defp unique_code_from(name) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    if Repo.exists?(from p in Platform, where: p.code == ^base) do
      "#{base}_#{:crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)}"
    else
      base
    end
  end
end
