defmodule CommunityHealth.TrustTest do
  use CommunityHealth.DataCase, async: true

  alias CommunityHealth.{Communities, Platforms, Reputation, Trust}

  setup do
    {:ok, platform, _token} = Platforms.register_platform("Underlined")
    {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")
    {:ok, _member} = Communities.ensure_member(community, "user-1")

    %{platform: platform, community: community}
  end

  describe "get_trust_level/2" do
    test "a brand-new member is low trust", %{community: community} do
      assert {:ok, %{trust_level: "low", account_age_days: 0, reputation_score: 0}} =
               Trust.get_trust_level(community, "user-1")
    end

    test "errors for a non-member", %{community: community} do
      assert {:error, :actor_not_found} = Trust.get_trust_level(community, "nobody")
    end

    test "reaches medium trust with a week of age and modest reputation", %{community: community} do
      backdate_member(community, "user-1", 8)
      set_score(community, "user-1", 15)

      assert {:ok, %{trust_level: "medium"}} = Trust.get_trust_level(community, "user-1")
    end

    test "reaches high trust with 30+ days of age and strong reputation", %{community: community} do
      backdate_member(community, "user-1", 31)
      set_score(community, "user-1", 150)

      assert {:ok, %{trust_level: "high"}} = Trust.get_trust_level(community, "user-1")
    end

    defp backdate_member(community, actor_external_id, days) do
      member = Communities.get_member(community, actor_external_id)
      backdated = NaiveDateTime.add(NaiveDateTime.utc_now(), -days * 24 * 60 * 60, :second) |> NaiveDateTime.truncate(:second)
      Ecto.Changeset.change(member, inserted_at: backdated) |> CommunityHealth.Repo.update!()
    end

    defp set_score(community, actor_external_id, score) do
      %Reputation.ReputationScore{}
      |> Reputation.ReputationScore.changeset(%{
        community_id: community.id,
        actor_external_id: actor_external_id,
        score: score
      })
      |> CommunityHealth.Repo.insert!()
    end
  end
end
