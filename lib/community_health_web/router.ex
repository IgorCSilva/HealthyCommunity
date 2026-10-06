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
    post "/events", EventController, :create
    get "/communities/:community_ref/rules", RuleController, :index
    post "/reports", ReportController, :create
    get "/communities/:community_ref/members/:actor_ref/reputation", ReputationController, :show
    get "/communities/:community_ref/members/:actor_ref/trust", TrustController, :show

    get "/communities/:community_ref/members/:actor_ref/role-progress/:role_code",
        RoleController,
        :role_progress

    get "/communities/:community_ref/reports/:report_id/case", ModerationController, :show_case

    post "/communities/:community_ref/cases/:case_id/decisions",
         ModerationController,
         :create_decision

    post "/communities/:community_ref/decisions/:decision_id/actions",
         ModerationController,
         :create_action

    post "/communities/:community_ref/actions/:action_id/appeals",
         ModerationController,
         :create_appeal

    post "/communities/:community_ref/appeals/:appeal_id/resolve",
         ModerationController,
         :resolve_appeal
  end
end
