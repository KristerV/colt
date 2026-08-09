defmodule Colt.Services.Sales.SetChecklistItem do
  @moduledoc """
  Tick or untick one checklist item for one contact.

  Tick rows are created lazily, so the first tick inserts and every tick after
  that updates. That keeps an untouched contact free of rows entirely and lets
  the campaign checklist be edited without any backfill.
  """

  alias Colt.Resources.{ChecklistItem, ContactChecklistItem, StatusEvent}
  alias Colt.Services.Sales.RecordStatusEvent

  @doc """
  Mark `checklist_item_id` done (`done?: true`) or not done for `contact_id`.
  Returns `{:ok, contact_checklist_item}`.
  """
  def run(contact_id, checklist_item_id, done?, opts \\ [])
      when is_binary(contact_id) and is_binary(checklist_item_id) and is_boolean(done?) do
    actor = Keyword.get(opts, :actor)
    auth? = actor != nil
    done_at = if done?, do: DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, existing} <- find(contact_id, checklist_item_id, actor, auth?),
         {:ok, tick} <- upsert(existing, contact_id, checklist_item_id, done_at, actor, auth?),
         {:ok, item} <- Ash.get(ChecklistItem, checklist_item_id, actor: actor, authorize?: auth?) do
      RecordStatusEvent.for_contact(contact_id, :checklist, nil, item.name,
        actor: actor,
        reason: StatusEvent.checklist_reason(done?)
      )

      {:ok, tick}
    end
  end

  defp find(contact_id, checklist_item_id, actor, auth?) do
    with {:ok, ticks} <-
           ContactChecklistItem.list_for_contact(contact_id, actor: actor, authorize?: auth?) do
      {:ok, Enum.find(ticks, &(&1.checklist_item_id == checklist_item_id))}
    end
  end

  defp upsert(nil, contact_id, checklist_item_id, done_at, actor, auth?) do
    ContactChecklistItem.create(contact_id, checklist_item_id, %{done_at: done_at},
      actor: actor,
      authorize?: auth?
    )
  end

  defp upsert(tick, _contact_id, _checklist_item_id, done_at, actor, auth?) do
    ContactChecklistItem.set_done(tick, done_at, actor: actor, authorize?: auth?)
  end
end
