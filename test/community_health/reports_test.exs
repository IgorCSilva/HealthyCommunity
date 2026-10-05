defmodule CommunityHealth.ReportsTest do
  use CommunityHealth.DataCase, async: true

  alias CommunityHealth.{Communities, Platforms, Reports, Rules}

  setup do
    {:ok, platform, _token} = Platforms.register_platform("Underlined")
    {:ok, community} = Communities.ensure_community(platform, "default", "Underlined")

    {:ok, _rule} =
      Rules.create_rule(community, %{code: "PERSONAL_ATTACK", name: "Personal attack", severity: "high"})

    %{platform: platform, community: community}
  end

  @attrs %{
    reporter_external_id: "user-1",
    resource_type: "post",
    resource_ref: "post-1",
    reason: "PERSONAL_ATTACK"
  }

  describe "submit_report/3" do
    test "records a report and registers its resource on first sight", %{
      platform: platform,
      community: community
    } do
      assert {:ok, report} = Reports.submit_report(platform, community, @attrs)
      assert report.reporter_external_id == "user-1"
      assert report.reason == "PERSONAL_ATTACK"
      assert report.status == "pending"
    end

    test "is idempotent on (platform, resource, reporter) — a retry returns the original row", %{
      platform: platform,
      community: community
    } do
      {:ok, first} = Reports.submit_report(platform, community, @attrs)
      {:ok, second} = Reports.submit_report(platform, community, %{@attrs | reason: "DIFFERENT"})

      assert first.id == second.id
      assert second.reason == "PERSONAL_ATTACK"
    end

    test "a different reporter on the same resource creates a second report", %{
      platform: platform,
      community: community
    } do
      {:ok, first} = Reports.submit_report(platform, community, @attrs)
      {:ok, second} = Reports.submit_report(platform, community, %{@attrs | reporter_external_id: "user-2"})

      assert first.id != second.id
      assert first.resource_id == second.resource_id
    end

    test "the same reporter on a different resource creates a second report", %{
      platform: platform,
      community: community
    } do
      {:ok, first} = Reports.submit_report(platform, community, @attrs)

      {:ok, second} =
        Reports.submit_report(platform, community, %{
          @attrs
          | resource_ref: "post-2"
        })

      assert first.id != second.id
      assert first.resource_id != second.resource_id
    end
  end
end
