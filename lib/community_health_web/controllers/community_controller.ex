defmodule CommunityHealthWeb.CommunityController do
  use CommunityHealthWeb, :controller

  alias CommunityHealth.Communities

  def create(conn, %{"external_ref" => external_ref, "name" => name}) do
    case Communities.ensure_community(conn.assigns.current_platform, external_ref, name) do
      {:ok, community} ->
        json(conn, %{
          id: community.id,
          external_ref: community.external_ref,
          name: community.name
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors_on(changeset)})
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
