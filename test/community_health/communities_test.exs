defmodule CommunityHealth.CommunitiesTest do
  use CommunityHealth.DataCase, async: true

  alias CommunityHealth.{Communities, Platforms}

  setup do
    {:ok, platform, _token} = Platforms.register_platform("Underlined")
    %{platform: platform}
  end

  describe "ensure_community/3" do
    test "creates a community on first call", %{platform: platform} do
      assert {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")
      assert community.external_ref == "default"
      assert community.name == "Underlined"
    end

    test "is idempotent on (platform, external_ref)", %{platform: platform} do
      {:ok, first} = Communities.ensure_community(platform, "default", "Underlined")
      {:ok, second} = Communities.ensure_community(platform, "default", "Underlined, Renamed")

      assert first.id == second.id
      assert second.name == "Underlined, Renamed"
    end

    test "the same external_ref is independent across platforms", %{platform: platform} do
      {:ok, other_platform, _token} = Platforms.register_platform("OtherApp")

      {:ok, a} = Communities.ensure_community(platform, "default", "Underlined")
      {:ok, b} = Communities.ensure_community(other_platform, "default", "OtherApp")

      assert a.id != b.id
    end
  end

  describe "ensure_member/2 and get_community/2" do
    test "ensures membership idempotently", %{platform: platform} do
      {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")

      assert {:ok, member} = Communities.ensure_member(community, "user-1")
      assert member.actor_external_id == "user-1"

      assert {:ok, member_again} = Communities.ensure_member(community, "user-1")
      assert member_again.id == member.id
    end

    test "get_community/2 returns nil for an unknown external_ref", %{platform: platform} do
      assert Communities.get_community(platform, "nonexistent") == nil
    end
  end
end
