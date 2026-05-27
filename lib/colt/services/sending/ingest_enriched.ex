defmodule Colt.Services.Sending.IngestEnriched do
  @moduledoc """
  Promote enriched CampaignCompanies into CampaignContacts.

  For every CampaignCompany in the given campaign with a non-null
  `picked_person_id`, insert a CampaignContact `:pending_approval` row
  and an empty Thread. Idempotent — already-promoted contacts are left
  alone via the `unique_per_campaign` identity upsert.
  """

  alias Colt.Resources.{Campaign, CampaignCompany, CampaignContact, Person, Thread}

  def run(campaign_id, opts \\ []) when is_binary(campaign_id) do
    actor = Keyword.get(opts, :actor)

    with {:ok, picks} <- load_picks(campaign_id, actor),
         {:ok, inserted_contacts} <- promote_all(campaign_id, picks, actor),
         {:ok, _} <- maybe_enqueue_auto(campaign_id, inserted_contacts, actor) do
      {:ok, %{candidates: length(picks), inserted: length(inserted_contacts)}}
    end
  end

  defp maybe_enqueue_auto(campaign_id, contacts, actor) do
    case Campaign.get(campaign_id, actor: actor, authorize?: actor != nil) do
      {:ok, %{auto_approve_on?: true}} ->
        Enum.each(contacts, &Colt.Jobs.AutoDraftAndApprove.enqueue(&1.id))
        {:ok, :enqueued}

      _ ->
        {:ok, :skipped}
    end
  end

  defp load_picks(campaign_id, actor) do
    rows =
      campaign_id
      |> CampaignCompany.list_for_campaign!(actor: actor, authorize?: actor != nil)
      |> Enum.filter(&(&1.picked_person_id != nil))

    {:ok, rows}
  end

  defp promote_all(campaign_id, picks, actor) do
    inserted =
      Enum.reduce(picks, [], fn cc, acc ->
        case promote_one(campaign_id, cc.picked_person_id, actor) do
          {:ok, contact} -> [contact | acc]
          {:error, _} -> acc
        end
      end)

    {:ok, Enum.reverse(inserted)}
  end

  defp promote_one(campaign_id, person_id, actor) do
    with {:ok, _} <- maybe_dev_rewrite_email(person_id, actor),
         {:ok, contact} <-
           CampaignContact.promote(campaign_id, person_id,
             actor: actor,
             authorize?: actor != nil
           ),
         {:ok, _thread} <-
           Thread.create_for_contact(contact.id,
             actor: actor,
             authorize?: actor != nil
           ) do
      {:ok, contact}
    end
  end

  # Dev-only: replace person.email with a plus-tagged alias on a personal
  # inbox so every test send lands in the developer's mailbox instead of
  # the real prospect. Idempotent — already-rewritten addresses are left
  # alone. Production no-ops.
  defp maybe_dev_rewrite_email(person_id, actor) do
    if Application.get_env(:colt, :dev_recipient_rewrite, false) do
      with {:ok, person} <- Ash.get(Person, person_id, actor: actor, authorize?: actor != nil),
           false <- already_rewritten?(person.email),
           {:ok, rewritten} <- rewrite(person.email) do
        Person.set_email(person, rewritten, actor: actor, authorize?: actor != nil)
      else
        true -> {:ok, :already_rewritten}
        {:error, _} = err -> err
        :no_email -> {:ok, :no_email}
      end
    else
      {:ok, :prod}
    end
  end

  defp already_rewritten?(nil), do: true
  defp already_rewritten?(email), do: String.ends_with?(email, "@krister.ee")

  defp rewrite(nil), do: :no_email

  defp rewrite(email) when is_binary(email) do
    slug =
      email
      |> String.downcase()
      |> String.replace("@", "-at-")
      |> String.replace(".", "-")
      |> String.replace(~r/[^a-z0-9\-]/, "")

    {:ok, "test+#{slug}@krister.ee"}
  end
end
