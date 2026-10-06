defmodule CommunityHealth.ReputationTest do
  use CommunityHealth.DataCase, async: true
  use Oban.Testing, repo: CommunityHealth.Repo

  alias CommunityHealth.{Actions, Communities, Platforms, Reputation}
  alias CommunityHealth.Reputation.ReputationRollupWorker

  setup do
    {:ok, platform, _token} = Platforms.register_platform("Underlined")
    {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")

    %{platform: platform, community: community}
  end

  @event_attrs %{
    actor_external_id: "user-1",
    action_type: "CREATE",
    resource_type: "post",
    resource_ref: "post-1",
    event_key: "post:create:post-1"
  }

  describe "record_event_for_action/2 (via Actions.record_action/3)" do
    test "records an event and enqueues a rollup when an active rule matches", %{
      platform: platform,
      community: community
    } do
      {:ok, _rule} = Reputation.create_rule(community, %{action_type: "CREATE", points: 1})

      {:ok, _action} = Actions.record_action(platform, community, @event_attrs)

      assert_enqueued(worker: ReputationRollupWorker, args: %{actor_external_id: "user-1"})
    end

    test "is a no-op when no rule matches the action_type", %{platform: platform, community: community} do
      {:ok, _action} = Actions.record_action(platform, community, @event_attrs)

      refute_enqueued(worker: ReputationRollupWorker)
      assert Reputation.get_score(community, "user-1") == %{score: 0, level: 1}
    end

    test "replaying the same event_key never double-awards", %{platform: platform, community: community} do
      {:ok, _rule} = Reputation.create_rule(community, %{action_type: "CREATE", points: 5})

      {:ok, _} = Actions.record_action(platform, community, @event_attrs)
      {:ok, _} = Actions.record_action(platform, community, @event_attrs)

      {:ok, _score} = Reputation.rollup_score(community.id, "user-1")
      assert Reputation.get_score(community, "user-1") == %{score: 5, level: 1}
    end

    test "a daily cap clamps same-day awards for the same action_type", %{
      platform: platform,
      community: community
    } do
      {:ok, _rule} = Reputation.create_rule(community, %{action_type: "COMMENT", points: 3, daily_cap: 5})

      {:ok, _} =
        Actions.record_action(platform, community, %{
          @event_attrs
          | action_type: "COMMENT",
            resource_ref: "comment-1",
            event_key: "comment:create:comment-1"
        })

      {:ok, _} =
        Actions.record_action(platform, community, %{
          @event_attrs
          | action_type: "COMMENT",
            resource_ref: "comment-2",
            event_key: "comment:create:comment-2"
        })

      Reputation.rollup_score(community.id, "user-1")

      # 3 (first comment) + 2 (second comment, clamped by the cap of 5) = 5
      assert Reputation.get_score(community, "user-1") == %{score: 5, level: 1}
    end

    test "negative-point rules are never capped", %{platform: platform, community: community} do
      {:ok, _rule} = Reputation.create_rule(community, %{action_type: "PENALTY", points: -10, daily_cap: 2})

      {:ok, _} =
        Actions.record_action(platform, community, %{
          @event_attrs
          | action_type: "PENALTY",
            event_key: "penalty:1"
        })

      Reputation.rollup_score(community.id, "user-1")
      assert Reputation.get_score(community, "user-1") == %{score: -10, level: 1}
    end
  end

  describe "get_score/2" do
    test "buckets the raw score into a 1-5 seedling level", %{community: community} do
      {:ok, _} =
        %CommunityHealth.Reputation.ReputationScore{}
        |> CommunityHealth.Reputation.ReputationScore.changeset(%{
          community_id: community.id,
          actor_external_id: "user-2",
          score: 200
        })
        |> CommunityHealth.Repo.insert()

      assert Reputation.get_score(community, "user-2") == %{score: 200, level: 4}
    end

    test "defaults to score 0, level 1 for an actor with no events", %{community: community} do
      assert Reputation.get_score(community, "nobody") == %{score: 0, level: 1}
    end
  end
end
