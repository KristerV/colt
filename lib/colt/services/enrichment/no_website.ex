defmodule Colt.Services.Enrichment.NoWebsite do
  @moduledoc """
  Decide what happens to a company we couldn't find a website for — after both
  the registry field and the Google fallback came up empty.

  * `require_website?` (default) → drop it as `:no_website`, as the funnel always did.
  * otherwise → keep it. Skip the website and ICP pills and go straight to the
    contact ladder on registry data alone.

  The second path exists because on the EE import only ~6.5% of companies carry a
  registry website while 97% carry a contact email: for the SME long tail, "no
  site" is normal, not a disqualification. It's opt-in because it costs the ICP
  check — no site means no summary means nothing for the classifier to read, so
  those companies are targeted on the structured filters alone.

  Both pills are marked `:skip`, never `:done`: nothing was checked, and the row
  shouldn't claim otherwise.
  """

  alias Colt.Jobs.Enrichment.ResolveContact
  alias Colt.Resources.CampaignCompany
  alias Colt.Services.Enrichment.Transition

  def run(cc, campaign, opts \\ []) do
    reason = Keyword.get(opts, :reason, "no website found")

    if campaign.require_website? do
      Transition.stage(cc, :website, :fall)
      {:ok, _} = Transition.terminate(cc, :no_website, reason: reason)
      :ok
    else
      # Persist the skip before broadcasting it. The live pills come from
      # PubSub, but a reload re-derives them from the CC's own columns — and
      # that derivation marks every stage before the frontier :done. Without
      # this flag a refresh would quietly upgrade these two pills to "passed".
      {:ok, cc} = CampaignCompany.mark_website_skipped(cc, authorize?: false)

      Transition.stage(cc, :website, :skip)
      Transition.stage(cc, :icp, :skip)
      %{campaign_company_id: cc.id} |> ResolveContact.new() |> Oban.insert!()
      :ok
    end
  end
end
