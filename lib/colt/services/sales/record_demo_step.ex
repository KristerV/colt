defmodule Colt.Services.Sales.RecordDemoStep do
  @moduledoc """
  Mirror one step of the `/demo` deck onto the contact who was watching:
  they started it, they reached the end, or they clicked a closing CTA.

  Only prospects who arrived through a personalised `?c=<contact_id>` link have
  a contact at all — cold deck traffic is anonymous and never reaches here.

  **First write wins.** The stamp on the contact is both the record and the
  guard: a prospect who reloads the deck and hits Play again has not started
  twice, and repeating the chip in their timeline would say less than one of
  them does. Every later call for the same step is a silent no-op.

  Reaching the end is the moment worth interrupting someone for, so that step —
  and only that step — also pings Discord. The CTA already has its own Discord
  alert further down the deck (the lead submit in `ColtWeb.DeckLive`), and a
  start is not yet news.

  Like `RecordStatusEvent`, this is a secondary concern that must never cost the
  visitor their playback: every path returns `:ok`, failures are logged.
  """

  require Logger

  alias Colt.Resources.{CampaignContact, StatusEvent}
  alias Colt.Services.Discord
  alias Colt.Services.Sales.RecordStatusEvent

  @steps [:started, :completed, :cta]

  @doc """
  Record `step` (`:started`, `:completed` or `:cta`) for `contact_id`. `opts`
  may carry `:cta_kind`, the label of the button clicked. Returns `:ok`.
  """
  def run(contact_id, step, opts \\ []) when is_binary(contact_id) and step in @steps do
    with {:ok, contact} <- fetch(contact_id),
         :ok <- unrecorded(contact, step),
         {:ok, _updated} <- stamp(contact, step) do
      RecordStatusEvent.for_contact(contact_id, :demo, nil, StatusEvent.demo_step(step),
        reason: Keyword.get(opts, :cta_kind)
      )

      notify(step, contact, opts)
      :ok
    else
      :already_recorded ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "record_demo_step #{step} failed for contact #{contact_id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  # The visitor has no actor, so every write here is unauthorised by necessity.
  defp fetch(contact_id), do: CampaignContact.get(contact_id, load: [:person], authorize?: false)

  defp unrecorded(contact, step) do
    case Map.fetch!(contact, field(step)) do
      nil -> :ok
      _at -> :already_recorded
    end
  end

  defp stamp(contact, step) do
    at = DateTime.utc_now() |> DateTime.truncate(:second)

    CampaignContact.record_demo_step(contact, %{field(step) => at}, authorize?: false)
  end

  defp field(:started), do: :demo_started_at
  defp field(:completed), do: :demo_completed_at
  defp field(:cta), do: :demo_cta_at

  defp notify(:completed, contact, _opts) do
    Discord.Notify.run("Demo watched to the end: #{who(contact)}")
  end

  defp notify(_step, _contact, _opts), do: :ok

  defp who(%{person: %{} = person}) do
    [person.name, person.email] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
  end

  defp who(_contact), do: "unknown contact"
end
