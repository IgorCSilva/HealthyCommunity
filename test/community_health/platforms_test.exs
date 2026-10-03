defmodule CommunityHealth.PlatformsTest do
  use CommunityHealth.DataCase, async: true

  alias CommunityHealth.Platforms

  describe "register_platform/1" do
    test "creates a platform with a slugified code and a usable token" do
      assert {:ok, platform, token} = Platforms.register_platform("Underlined")
      assert platform.name == "Underlined"
      assert platform.code == "underlined"
      assert is_binary(token)
      assert {:ok, authenticated} = Platforms.authenticate(token)
      assert authenticated.id == platform.id
    end

    test "disambiguates colliding codes" do
      {:ok, _first, _} = Platforms.register_platform("Underlined")
      assert {:ok, second, _} = Platforms.register_platform("underlined")
      assert second.code != "underlined"
    end
  end

  describe "authenticate/1" do
    test "rejects an unknown token" do
      assert {:error, :invalid_token} = Platforms.authenticate("not-a-real-token")
    end

    test "rejects a revoked key" do
      {:ok, platform, token} = Platforms.register_platform("Underlined")

      from(k in CommunityHealth.Platforms.ApiKey, where: k.platform_id == ^platform.id)
      |> CommunityHealth.Repo.update_all(set: [revoked_at: DateTime.utc_now()])

      assert {:error, :invalid_token} = Platforms.authenticate(token)
    end
  end
end
