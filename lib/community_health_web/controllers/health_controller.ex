defmodule CommunityHealthWeb.HealthController do
  use CommunityHealthWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
