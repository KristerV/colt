defmodule Colt.Resources.StatusEvent do
  @moduledoc """
  Unified feed entry for a Thread. Every status change — the sales moves and
  the sending transitions — writes one entry with an actor (nullable =
  system-generated), a human from/to, a kind, and an optional reason.
  Rendered inline in the timeline of both funnels.

  `:sales_stage` is **legacy, read-only**: it dates from when the sales funnel
  was a set of user-defined stages. Nothing writes it any more, but old rows
  must keep rendering, so the value stays in the constraint. Today's sales
  writes are `:next_action`, `:outcome` and `:checklist`.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "status_events"
    repo Colt.Repo

    custom_indexes do
      index [:thread_id]
    end

    references do
      reference :thread, on_delete: :delete
      reference :actor, on_delete: :nilify
    end
  end

  # A `:checklist` event stores the item name in `to` and the resulting state
  # in `reason`. These two constants are the contract between the writer
  # (`Colt.Services.Sales.SetChecklistItem`) and the timeline renderer, which
  # draws a real checkbox from it — keep them out of inline string literals so
  # the two can't drift apart.
  @checked "checked"
  @unchecked "unchecked"

  @doc "The `reason` value recording a checklist tick or untick."
  def checklist_reason(true), do: @checked
  def checklist_reason(false), do: @unchecked

  @doc "True when a `:checklist` event recorded a tick rather than an untick."
  def checklist_done?(%{kind: :checklist, reason: @checked}), do: true
  def checklist_done?(_), do: false

  @doc """
  The `to` value for one step of the `/demo` deck. Same contract as the
  checklist constants above: the writer (`Colt.Services.Sales.RecordDemoStep`)
  and the timeline renderer have to agree on these strings, so neither spells
  them inline.
  """
  def demo_step(:started), do: "started"
  def demo_step(:completed), do: "completed"
  def demo_step(:cta), do: "cta"

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :list_for_thread, args: [:thread_id]
    define :record, args: [:thread_id, :kind, :from, :to, :reason]
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    read :list_for_thread do
      argument :thread_id, :uuid, allow_nil?: false
      filter expr(thread_id == ^arg(:thread_id))
      prepare build(sort: [occurred_at: :asc])
    end

    create :record do
      description """
      Record one feed entry. `actor` is related from the acting user, or
      nil when called from a system/Oban context (`authorize?: false`,
      no actor).
      """

      accept [:thread_id, :kind, :from, :to, :reason]
      change relate_actor(:actor, allow_nil?: true)
    end
  end

  policies do
    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(thread.campaign_contact.campaign.owner_id == ^actor(:id))
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:destroy) do
      authorize_if expr(thread.campaign_contact.campaign.owner_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom,
      constraints: [
        one_of: [
          :send_status,
          :reply_category,
          :entry,
          :next_action,
          :outcome,
          :checklist,
          # what the prospect did inside the `/demo` deck; `to` is one of
          # `demo_steps/0` and, for "cta", `reason` names which button
          :demo,
          # legacy — written by the old user-defined stage funnel, still rendered
          :sales_stage
        ]
      ],
      allow_nil?: false,
      public?: true

    attribute :from, :string, public?: true
    attribute :to, :string, public?: true
    attribute :reason, :string, public?: true

    attribute :occurred_at, :utc_datetime_usec,
      allow_nil?: false,
      default: &DateTime.utc_now/0,
      public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :thread, Colt.Resources.Thread, allow_nil?: false, public?: true
    belongs_to :actor, Colt.Accounts.User, allow_nil?: true, public?: true
  end
end
