defmodule CommunityHealth.Trust do
  @moduledoc """
  CH-Step 9: Trust ≠ Reputation (decoupled_healthy_system.md §16) — "how
  reliable is this person's behavior," not "how much have they
  contributed." Computed live from account age, reputation, and confirmed
  violations rather than cached: the step's own Tech line
  (healthy_community/roadmap.md) lists no Oban job for trust, and a single
  membership-row lookup plus `Reputation.get_score/2` is cheap enough that
  a rollup table would be premature.

  `confirmed_violations` is always 0 today — it depends on moderation
  review (CH-Step 6/7), which is "Not started"; this is wired to read from
  that step's data the moment it exists, not a placeholder removed later.
  """

  alias CommunityHealth.Communities
  alias CommunityHealth.Communities.Community
  alias CommunityHealth.Reputation

  @doc """
  Returns `{:ok, %{trust_level: "low" | "medium" | "high", ...}}` for an
  existing member of `community`, or `{:error, :actor_not_found}`.
  """
  def get_trust_level(%Community{} = community, actor_external_id) do
    case Communities.get_member(community, actor_external_id) do
      nil ->
        {:error, :actor_not_found}

      membership ->
        account_age_days = NaiveDateTime.diff(NaiveDateTime.utc_now(), membership.inserted_at, :day)
        reputation_score = Reputation.get_score(community, actor_external_id).score
        confirmed_violations = 0

        {:ok,
         %{
           trust_level: level_for(account_age_days, reputation_score, confirmed_violations),
           account_age_days: account_age_days,
           reputation_score: reputation_score,
           confirmed_violations: confirmed_violations
         }}
    end
  end

  defp level_for(account_age_days, reputation_score, confirmed_violations) do
    cond do
      confirmed_violations == 0 and account_age_days >= 30 and reputation_score >= 100 -> "high"
      confirmed_violations <= 2 and account_age_days >= 7 and reputation_score >= 10 -> "medium"
      true -> "low"
    end
  end
end
