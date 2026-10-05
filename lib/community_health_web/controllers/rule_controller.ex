defmodule CommunityHealthWeb.RuleController do
  use CommunityHealthWeb, :controller

  alias CommunityHealth.Communities
  alias CommunityHealth.Rules

  def index(conn, %{"community_ref" => community_ref}) do
    case Communities.get_community(conn.assigns.current_platform, community_ref) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Community not found"}})

      community ->
        rules = Rules.list_active_rules(community)

        json(conn, %{
          data:
            Enum.map(rules, fn rule ->
              %{
                code: rule.code,
                name: rule.name,
                description: rule.description,
                severity: rule.severity
              }
            end)
        })
    end
  end
end
