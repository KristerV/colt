defmodule Colt.Services.Sales.CreateManualContact do
  @moduledoc """
  Create a hand-entered contact (found on the street / just registered) inside
  a campaign, and drop it into the funnel(s) the user picked. Not from
  enrichment — the form supplies the company and person outright.

  Reuses the ordinary creation paths, no bespoke actions:
    * company → `Company.upsert_basic` (real registry_code + market from the form)
    * person  → `Person.create_manual`
    * contact → `CampaignContact.promote` with `origin: :manual`
    * sales entry → `AutoEnter.run`, the exact path an interested reply takes

  A thread is always created so notes and (later) emails have somewhere to land.
  """

  alias Colt.Resources.{CampaignContact, Company, Person, Thread}
  alias Colt.Services.Sales.AutoEnter

  @doc """
  `attrs` carries the person fields (`:name`, `:title`, `:email`, `:phone`),
  the company fields (`:company_name`, `:registry_code`, `:market`, `:region`)
  and the funnel choices (`:in_funnel_sending?`, `:in_funnel_sales?`). Returns
  `{:ok, contact}`.
  """
  def run(campaign_id, attrs, opts \\ []) when is_binary(campaign_id) do
    actor = Keyword.get(opts, :actor)
    auth? = actor != nil

    with {:ok, company} <- create_company(attrs, actor, auth?),
         {:ok, person} <- create_person(company.id, attrs, actor, auth?),
         {:ok, contact} <- create_contact(campaign_id, person.id, attrs, actor, auth?),
         {:ok, _thread} <-
           Thread.create_for_contact(contact.id, actor: actor, authorize?: auth?),
         {:ok, contact} <- maybe_enter_sales(contact, campaign_id, attrs, opts) do
      {:ok, contact}
    end
  end

  defp create_company(attrs, actor, auth?) do
    Company.upsert_basic(
      %{
        registry_code: attrs[:registry_code],
        market: attrs[:market],
        name: attrs[:company_name],
        region: attrs[:region]
      },
      actor: actor,
      authorize?: auth?
    )
  end

  defp create_person(company_id, attrs, actor, auth?) do
    Person.create_manual(
      %{
        company_id: company_id,
        name: attrs[:name],
        title: attrs[:title],
        email: attrs[:email],
        phone: attrs[:phone]
      },
      actor: actor,
      authorize?: auth?
    )
  end

  defp create_contact(campaign_id, person_id, attrs, actor, auth?) do
    CampaignContact.promote(
      campaign_id,
      person_id,
      %{origin: :manual, in_funnel_sending?: attrs[:in_funnel_sending?] == true},
      actor: actor,
      authorize?: auth?
    )
  end

  # Sales entry runs the same seed → first-active-stage → StatusEvent path as an
  # auto-entered interested reply, so nothing is special-cased for manual leads.
  defp maybe_enter_sales(contact, campaign_id, %{in_funnel_sales?: true}, opts) do
    case AutoEnter.run(contact.id, campaign_id, opts) do
      {:ok, %CampaignContact{} = updated} -> {:ok, updated}
      {:ok, :already_in} -> {:ok, contact}
      other -> other
    end
  end

  defp maybe_enter_sales(contact, _campaign_id, _attrs, _opts), do: {:ok, contact}
end
