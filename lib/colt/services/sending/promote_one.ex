defmodule Colt.Services.Sending.PromoteOne do
  @moduledoc """
  Pull-based promotion: mint exactly one CampaignContact from the enriched
  pool on demand.

  The enriched pool *is* the queue — a `CampaignCompany` with a non-null
  `picked_person_id`. A `CampaignContact{:pending_approval}` (+ empty Thread)
  is created only when something pulls it: the Write view when it has nothing
  pending, or the auto starter for each open send slot.

  `run/2` finds the next un-promoted candidate and promotes it. Returns
  `{:ok, contact}` or `{:ok, :none}` when the pool is exhausted.

  Idempotent via the `unique_per_campaign` identity, so a concurrent double
  pull collapses to a single contact row.
  """

  alias Colt.Resources.{CampaignCompany, CampaignContact, Person, Thread}

  def run(campaign_id, opts \\ []) when is_binary(campaign_id) do
    actor = Keyword.get(opts, :actor)

    case CampaignCompany.next_unpromoted(campaign_id, actor: actor, authorize?: actor != nil) do
      {:ok, %CampaignCompany{picked_person_id: person_id}} when is_binary(person_id) ->
        promote_person(campaign_id, person_id, opts)

      {:ok, _} ->
        {:ok, :none}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Promote a specific (campaign, person) into a pending contact with an empty
  thread. Shared by `run/2` and the bulk `IngestEnriched` dev/admin utility.
  """
  def promote_person(campaign_id, person_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, _} <- maybe_dev_rewrite_email(person_id, actor),
         {:ok, contact} <-
           CampaignContact.promote(campaign_id, person_id,
             actor: actor,
             authorize?: actor != nil
           ),
         {:ok, _thread} <-
           Thread.create_for_contact(contact.id, actor: actor, authorize?: actor != nil) do
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
