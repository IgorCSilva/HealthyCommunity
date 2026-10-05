defmodule CommunityHealth.ActionsTest do
  use CommunityHealth.DataCase, async: true

  alias CommunityHealth.{Actions, Communities, Platforms}

  setup do
    {:ok, platform, _token} = Platforms.register_platform("Underlined")
    {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")
    %{platform: platform, community: community}
  end

  @attrs %{
    actor_external_id: "user-1",
    action_type: "CREATE",
    resource_type: "post",
    resource_ref: "post-1",
    event_key: "post:create:post-1"
  }

  describe "record_action/3" do
    test "records an action and registers its resource on first sight", %{
      platform: platform,
      community: community
    } do
      assert {:ok, action} = Actions.record_action(platform, community, @attrs)
      assert action.actor_external_id == "user-1"
      assert action.action_type == "CREATE"
      assert action.event_key == "post:create:post-1"
    end

    test "is idempotent on (platform, event_key) — a retry returns the original row", %{
      platform: platform,
      community: community
    } do
      {:ok, first} = Actions.record_action(platform, community, @attrs)

      # A retried/replayed call with the same event_key but a different
      # action_type must still return the *original* row untouched — the
      # event_key, not the payload, is the idempotency contract.
      {:ok, second} =
        Actions.record_action(platform, community, %{@attrs | action_type: "DIFFERENT"})

      assert first.id == second.id
      assert second.action_type == "CREATE"
    end

    test "the same event_key is independent across platforms", %{
      platform: platform,
      community: community
    } do
      {:ok, other_platform, _token} = Platforms.register_platform("OtherApp")
      {:ok, other_community} = Communities.ensure_community(other_platform, "default", "OtherApp")

      {:ok, a} = Actions.record_action(platform, community, @attrs)
      {:ok, b} = Actions.record_action(other_platform, other_community, @attrs)

      assert a.id != b.id
    end

    test "a different resource_ref under the same event_key prefix creates a second resource/action",
         %{platform: platform, community: community} do
      {:ok, first} = Actions.record_action(platform, community, @attrs)

      {:ok, second} =
        Actions.record_action(platform, community, %{
          @attrs
          | resource_ref: "post-2",
            event_key: "post:create:post-2"
        })

      assert first.id != second.id
      assert first.resource_id != second.resource_id
    end
  end
end
