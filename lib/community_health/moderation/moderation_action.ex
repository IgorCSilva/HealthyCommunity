defmodule CommunityHealth.Moderation.ModerationAction do
  use Ecto.Schema
  import Ecto.Changeset

  @action_types ~w(content_removed warning content_hidden comment_locked temporary_suspension permanent_ban)
  @user_targeted_action_types ~w(warning temporary_suspension permanent_ban)

  schema "moderation_actions" do
    field :target_actor_external_id, :string
    field :action_type, :string
    field :duration_days, :integer
    field :reason, :string

    belongs_to :moderation_decision, CommunityHealth.Moderation.ModerationDecision

    timestamps(updated_at: false)
  end

  def changeset(action, attrs) do
    action
    |> cast(attrs, [
      :moderation_decision_id,
      :target_actor_external_id,
      :action_type,
      :duration_days,
      :reason
    ])
    |> validate_required([:moderation_decision_id, :action_type, :reason])
    |> validate_inclusion(:action_type, @action_types)
    |> validate_target_actor()
    |> foreign_key_constraint(:moderation_decision_id)
  end

  # warning/temporary_suspension/permanent_ban discipline a *user*, so they
  # need a resolvable target; content_removed/content_hidden/comment_locked
  # only ever touch the resource itself and can proceed without one — CH's
  # resources have no owner column, so this is sometimes unresolvable (see
  # ModerationCase.reported_actor_external_id).
  defp validate_target_actor(changeset) do
    action_type = get_field(changeset, :action_type)
    target = get_field(changeset, :target_actor_external_id)

    if action_type in @user_targeted_action_types and is_nil(target) do
      add_error(
        changeset,
        :target_actor_external_id,
        "is required for #{action_type} actions, but CH could not derive the reported content's author"
      )
    else
      changeset
    end
  end
end
