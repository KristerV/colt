defmodule Colt.Resources.StatusEvent do
  @moduledoc """
  Unified feed entry for a Thread. Every status change — the sales-stage
  moves and the existing sending transitions — writes one entry with an
  actor (nullable = system-generated), a human from/to, a kind, and an
  optional reason. Rendered inline in the timeline of both funnels.
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

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :list_for_thread, args: [:thread_id]
    define :last_stage_change_for_thread, args: [:thread_id]
    define :stage_changes_for_threads, args: [:thread_ids]
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

    read :last_stage_change_for_thread do
      description "Most recent sales-stage move (or entry) on a thread — drives days-in-stage."
      argument :thread_id, :uuid, allow_nil?: false
      filter expr(thread_id == ^arg(:thread_id) and kind in [:sales_stage, :entry])
      prepare build(sort: [occurred_at: :desc], limit: 1)
      get? true
    end

    read :stage_changes_for_threads do
      description "All sales-stage moves/entries for a set of threads, newest first — batches days-in-stage across the funnel board."
      argument :thread_ids, {:array, :uuid}, allow_nil?: false
      filter expr(thread_id in ^arg(:thread_ids) and kind in [:sales_stage, :entry])
      prepare build(sort: [occurred_at: :desc])
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
      constraints: [one_of: [:sales_stage, :send_status, :reply_category, :entry]],
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
