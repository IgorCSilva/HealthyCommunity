defmodule CommunityHealthWeb.EventController do
  use CommunityHealthWeb, :controller

  alias CommunityHealth.Actions
  alias CommunityHealth.Communities

  def create(conn, %{
        "community_ref" => community_ref,
        "actor_id" => actor_id,
        "action_type" => action_type,
        "resource_type" => resource_type,
        "resource_ref" => resource_ref,
        "event_key" => event_key
      } = params) do
    case Communities.get_community(conn.assigns.current_platform, community_ref) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Community not found"}})

      community ->
        attrs = %{
          actor_external_id: actor_id,
          action_type: action_type,
          resource_type: resource_type,
          resource_ref: resource_ref,
          event_key: event_key,
          context: Map.get(params, "context", %{}),
          occurred_at: parse_occurred_at(params["occurred_at"])
        }

        case Actions.record_action(conn.assigns.current_platform, community, attrs) do
          {:ok, action} ->
            json(conn, %{
              id: action.id,
              event_key: action.event_key,
              action_type: action.action_type,
              resource_type: resource_type,
              resource_ref: resource_ref,
              actor_external_id: action.actor_external_id,
              occurred_at: action.occurred_at
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{errors: errors_on(changeset)})
        end
    end
  end

  defp parse_occurred_at(nil), do: DateTime.utc_now()

  defp parse_occurred_at(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
