defmodule CommunityHealth.RulesTest do
  use CommunityHealth.DataCase, async: true

  alias CommunityHealth.{Communities, Platforms, Rules}

  setup do
    {:ok, platform, _token} = Platforms.register_platform("Underlined")
    {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")
    %{platform: platform, community: community}
  end

  describe "create_rule/2" do
    test "adds an active rule to a community", %{community: community} do
      assert {:ok, rule} =
               Rules.create_rule(community, %{
                 code: "PERSONAL_ATTACK",
                 name: "Personal attack",
                 severity: "high"
               })

      assert rule.active == true
      assert rule.community_id == community.id
    end

    test "rejects a duplicate code within the same community", %{community: community} do
      attrs = %{code: "SPAM", name: "Spam", severity: "low"}
      assert {:ok, _} = Rules.create_rule(community, attrs)
      assert {:error, changeset} = Rules.create_rule(community, attrs)
      assert "has already been taken" in errors_on(changeset).community_id
    end

    test "rejects an invalid severity", %{community: community} do
      assert {:error, changeset} =
               Rules.create_rule(community, %{code: "SPAM", name: "Spam", severity: "extreme"})

      assert "is invalid" in errors_on(changeset).severity
    end

    test "the same code is independent across communities", %{platform: platform} do
      {:ok, other_community} = Communities.ensure_community(platform, "other", "Other")
      attrs = %{code: "SPAM", name: "Spam", severity: "low"}

      assert {:ok, _} = Rules.create_rule(other_community, attrs)
    end
  end

  describe "list_active_rules/1 and get_active_rule/2" do
    test "only returns active rules", %{community: community} do
      {:ok, _} = Rules.create_rule(community, %{code: "SPAM", name: "Spam", severity: "low"})

      {:ok, inactive} =
        Rules.create_rule(community, %{
          code: "OLD_RULE",
          name: "Old rule",
          severity: "low",
          active: false
        })

      codes = community |> Rules.list_active_rules() |> Enum.map(& &1.code)
      assert codes == ["SPAM"]
      refute inactive.id in Enum.map(Rules.list_active_rules(community), & &1.id)
    end

    test "get_active_rule/2 finds an active rule by code, nil otherwise", %{community: community} do
      {:ok, _} = Rules.create_rule(community, %{code: "SPAM", name: "Spam", severity: "low"})

      assert %{code: "SPAM"} = Rules.get_active_rule(community, "SPAM")
      assert Rules.get_active_rule(community, "NOT_A_RULE") == nil
    end
  end
end
