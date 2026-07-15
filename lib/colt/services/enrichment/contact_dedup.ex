defmodule Colt.Services.Enrichment.ContactDedup do
  @moduledoc """
  Is this address already spoken for by another company in the same campaign?

  One human often registers several companies — on the EE import 180 addresses
  are the registry contact for two or more, covering ~5% of rows. Without this
  check the owner rung happily picks the same person once per company, and they
  receive four near-identical cold emails from us in one campaign. That reads as
  spam from their side, and it is.

  `Person` can't answer this: it belongs to a company, so the same human is a
  separate row per company and `picked_person_id` never collides. The comparison
  has to be on the address, which is why `CampaignCompany.picked_email` exists.

  This is the cheap pre-check that keeps the funnel tidy. It is **not** the
  guarantee — two jobs racing on the same address both see `false` here. The
  `campaign_picked_email` identity is what actually holds the line; this just
  means we rarely have to find out.
  """

  alias Colt.Resources.CampaignCompany

  # The index behind `identity :campaign_picked_email`. We match on the
  # constraint *name* rather than the error's :field, because Ash reports a
  # composite-identity violation against the identity's first field —
  # :campaign_id — which `identity :campaign_company` ([:campaign_id,
  # :company_id]) also reports. The field alone can't tell the two apart.
  @constraint "campaign_companies_campaign_picked_email_index"

  @doc """
  True when another campaign company has already picked `email`.

  `except_id` is the campaign company asking, so re-running a rung against a row
  that already holds the address doesn't call itself a duplicate.
  """
  def taken?(campaign_id, email, except_id \\ nil)

  def taken?(_campaign_id, email, _except_id) when not is_binary(email), do: false

  def taken?(campaign_id, email, except_id) do
    case CampaignCompany.picked_with_email(campaign_id, normalize(email), authorize?: false) do
      {:ok, rows} -> Enum.any?(rows, &(&1.id != except_id))
      _ -> false
    end
  end

  @doc """
  Who already holds `email` in this campaign, for a reason string the user can
  act on. Returns `{:ok, campaign_company}` or `:none`.
  """
  def holder(campaign_id, email, except_id \\ nil)

  def holder(_campaign_id, email, _except_id) when not is_binary(email), do: :none

  def holder(campaign_id, email, except_id) do
    with {:ok, rows} <-
           CampaignCompany.picked_with_email(campaign_id, normalize(email),
             load: [:company],
             authorize?: false
           ),
         %CampaignCompany{} = cc <- Enum.find(rows, &(&1.id != except_id)) do
      {:ok, cc}
    else
      _ -> :none
    end
  end

  @doc "The form an address is compared and stored in. Addresses are case-insensitive in practice."
  def normalize(email) when is_binary(email), do: email |> String.trim() |> String.downcase()
  def normalize(other), do: other

  @doc """
  Did this write fail because another company in the campaign already holds the
  address? Distinguishes a lost race — which the caller should handle by trying
  the next rung — from a genuine failure, which it should not swallow.
  """
  def duplicate_error?(error) do
    error
    |> Ash.Error.to_error_class()
    |> Map.get(:errors, [])
    |> Enum.any?(fn
      %{private_vars: vars} when is_list(vars) -> vars[:constraint] == @constraint
      _ -> false
    end)
  end

  @doc false
  def constraint_name, do: @constraint
end
