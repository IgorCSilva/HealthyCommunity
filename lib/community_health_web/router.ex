defmodule CommunityHealthWeb.Router do
  use CommunityHealthWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug CommunityHealthWeb.Plugs.ApiKeyAuth
  end

  scope "/", CommunityHealthWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  scope "/v1", CommunityHealthWeb do
    pipe_through [:api, :authenticated]

    post "/communities", CommunityController, :create
    put "/communities/:community_ref/members/:actor_ref", MembershipController, :ensure
  end
end
