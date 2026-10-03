defmodule CommunityHealthWeb.Plugs.ApiKeyAuth do
  @moduledoc """
  Authenticates every `/v1` request via `Authorization: Bearer <token>`,
  per CH-Step 1. On success assigns `conn.assigns.current_platform`; on
  failure halts with 401 before any controller action runs.
  """

  import Plug.Conn
  alias CommunityHealth.Platforms

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, platform} <- Platforms.authenticate(token) do
      assign(conn, :current_platform, platform)
    else
      _ -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{errors: %{detail: "Unauthorized"}})
    |> halt()
  end
end
