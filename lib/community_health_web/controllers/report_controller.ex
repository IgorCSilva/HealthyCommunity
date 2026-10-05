defmodule CommunityHealthWeb.ReportController do
  use CommunityHealthWeb, :controller

  alias CommunityHealth.Communities
  alias CommunityHealth.Reports
  alias CommunityHealth.Rules

  def create(conn, %{
        "community_ref" => community_ref,
        "reporter_id" => reporter_id,
        "resource_type" => resource_type,
        "resource_ref" => resource_ref,
        "reason" => reason
      } = params) do
    case Communities.get_community(conn.assigns.current_platform, community_ref) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Community not found"}})

      community ->
        case Rules.get_active_rule(community, reason) do
          nil ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{errors: %{reason: "is not an active rule for this community"}})

          _rule ->
            attrs = %{
              reporter_external_id: reporter_id,
              resource_type: resource_type,
              resource_ref: resource_ref,
              reason: reason,
              description: params["description"]
            }

            case Reports.submit_report(conn.assigns.current_platform, community, attrs) do
              {:ok, report} ->
                json(conn, %{
                  id: report.id,
                  reason: report.reason,
                  status: report.status,
                  resource_type: resource_type,
                  resource_ref: resource_ref,
                  reporter_external_id: report.reporter_external_id
                })

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{errors: errors_on(changeset)})
            end
        end
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
