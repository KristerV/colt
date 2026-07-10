defmodule Colt.Services.Sales.UpdateContact do
  @moduledoc """
  Edit a contact from the sales funnel. The person fields (name, title, email,
  phone) are always editable, whatever the contact's origin. The company block
  is only touched for a hand-entered (`origin: :manual`) contact — an
  enrichment contact's company is shared registry data across every campaign,
  so it stays read-only here and this service leaves it untouched.

  Reuses ordinary update paths, no bespoke actions:
    * person  → `Person.update_manual` (always)
    * company → `Company.update_basic` (manual origin only)
    * funnels → `CampaignContact.set_funnels`, then `AutoEnter.run` when sales
      membership is turned on and no stage is set yet
  """

  alias Colt.Resources.{CampaignContact, Company, Person}
  alias Colt.Services.Sales.AutoEnter

  @doc """
  `contact` is a loaded `CampaignContact` with `person: :company`. `attrs`
  carries the same keys as `CreateManualContact` (`:name`, `:title`, `:email`,
  `:phone`, `:company_name`, `:registry_code`, `:market`, `:region`,
  `:website`, `:in_funnel_sending?`, `:in_funnel_sales?`). Company fields are
  ignored unless the contact was hand-entered. Returns `{:ok, contact}`.
  """
  def run(%CampaignContact{} = contact, attrs, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    auth? = actor != nil

    with {:ok, _person} <- update_person(contact.person, attrs, actor, auth?),
         {:ok, _company} <- maybe_update_company(contact, attrs, actor, auth?),
         {:ok, contact} <- update_funnels(contact, attrs, opts, actor, auth?) do
      {:ok, contact}
    end
  end

  defp update_person(person, attrs, actor, auth?) do
    Person.update_manual(
      person,
      %{
        name: attrs[:name],
        title: attrs[:title],
        email: attrs[:email],
        phone: attrs[:phone]
      },
      actor: actor,
      authorize?: auth?
    )
  end

  # Only a manual contact's placeholder company is editable. An enrichment
  # contact's company is registry data shared across campaigns — left alone.
  defp maybe_update_company(%{origin: :manual, person: %{company: company}}, attrs, actor, auth?) do
    {url, source} =
      case attrs[:website] do
        url when is_binary(url) -> {url, :manual}
        _ -> {nil, nil}
      end

    Company.update_basic(
      company,
      %{
        name: attrs[:company_name],
        region: attrs[:region],
        registry_code: attrs[:registry_code],
        market: attrs[:market],
        website_url: url,
        website_source: source
      },
      actor: actor,
      authorize?: auth?
    )
  end

  defp maybe_update_company(_contact, _attrs, _actor, _auth?), do: {:ok, :unchanged}

  # Write both flags first; if sales is now on but no stage is set yet (the
  # contact was outside the sales funnel), run the same AutoEnter path a fresh
  # manual sales lead takes to seed the first active stage.
  defp update_funnels(contact, attrs, opts, actor, auth?) do
    with {:ok, contact} <-
           CampaignContact.set_funnels(
             contact,
             %{
               in_funnel_sending?: attrs[:in_funnel_sending?] == true,
               in_funnel_sales?: attrs[:in_funnel_sales?] == true
             },
             actor: actor,
             authorize?: auth?
           ) do
      maybe_enter_sales(contact, attrs, opts)
    end
  end

  defp maybe_enter_sales(%{in_funnel_sales?: true, sales_stage_id: nil} = contact, _attrs, opts) do
    case AutoEnter.run(contact.id, contact.campaign_id, opts) do
      {:ok, %CampaignContact{} = updated} -> {:ok, updated}
      {:ok, :already_in} -> {:ok, contact}
      other -> other
    end
  end

  defp maybe_enter_sales(contact, _attrs, _opts), do: {:ok, contact}
end
