defmodule Colt.Resources.OutboundEmail do
  @moduledoc """
  One outbound email — drafted, scheduled, sent, or terminal (bounced /
  failed / skipped). AI-vs-user content fields sit side-by-side so the
  writer learning loop can later diff them (effective = `user_? || ai_?`).
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "outbound_emails"
    repo Colt.Repo

    references do
      reference :thread, on_delete: :delete
      reference :email_account, on_delete: :nilify
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :list_for_thread, args: [:thread_id]
    define :list_due, args: [:now, :limit]
    define :list_today_for_account, args: [:email_account_id, :day_start, :day_end]
    define :list_for_account_window, args: [:email_account_id, :from, :to]
    define :recent_to_recipient, args: [:recipient_email, :campaign_id, :since]
    define :find_to_recipient_in_inbox, args: [:email_account_id, :recipient_email]
    define :list_halt_eligible_for_thread, args: [:thread_id]
    define :next_scheduled_for_thread, args: [:thread_id]
    define :list_user_edited_for_sequence, args: [:sequence_id, :limit]

    define :create_draft,
      args: [:thread_id, :step_position, :ai_subject, :ai_body]

    define :create_manual_reply

    define :update_user_fields, args: [:user_subject, :user_body]

    define :mark_approved
    define :schedule, args: [:scheduled_at, :email_account_id]
    define :mark_sent, args: [:nylas_message_id, :nylas_thread_id, :sent_at]
    define :mark_bounced, args: [:bounce_reason]
    define :mark_failed
    define :mark_skipped
    define :update_tracking_counts, args: [:opens_count, :clicks_count]
    define :list_recent_for_tracking, args: [:since]
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    read :list_for_thread do
      argument :thread_id, :uuid, allow_nil?: false
      filter expr(thread_id == ^arg(:thread_id))
      prepare build(sort: [inserted_at: :asc])
    end

    read :list_due do
      description "Outbound emails ready to send (status :scheduled, due before :now)."
      argument :now, :utc_datetime_usec, allow_nil?: false
      argument :limit, :integer, allow_nil?: false

      filter expr(status == :scheduled and scheduled_at <= ^arg(:now))

      prepare build(sort: [scheduled_at: :asc])
      prepare build(limit: arg(:limit))
    end

    read :list_today_for_account do
      description """
      Outbound emails for an account whose scheduled_at falls inside the
      given window. Includes :scheduled and :sent so the burst scheduler
      sees already-fired sends. Sorted by scheduled_at asc.
      """

      argument :email_account_id, :uuid, allow_nil?: false
      argument :day_start, :utc_datetime_usec, allow_nil?: false
      argument :day_end, :utc_datetime_usec, allow_nil?: false

      filter expr(
               email_account_id == ^arg(:email_account_id) and
                 status in [:scheduled, :sent] and
                 scheduled_at >= ^arg(:day_start) and scheduled_at < ^arg(:day_end)
             )

      prepare build(sort: [scheduled_at: :asc])
    end

    read :list_for_account_window do
      description """
      All outbound rows for an account whose effective timestamp
      (sent_at if present, otherwise scheduled_at) falls inside the
      [from, to) window. Used by the per-account stats view.
      """

      argument :email_account_id, :uuid, allow_nil?: false
      argument :from, :utc_datetime_usec, allow_nil?: false
      argument :to, :utc_datetime_usec, allow_nil?: false

      filter expr(
               email_account_id == ^arg(:email_account_id) and
                 status in [:scheduled, :sent, :failed, :bounced] and
                 fragment("coalesce(?, ?)", sent_at, scheduled_at) >= ^arg(:from) and
                 fragment("coalesce(?, ?)", sent_at, scheduled_at) < ^arg(:to)
             )

      prepare build(sort: [scheduled_at: :asc])
    end

    read :recent_to_recipient do
      description """
      Outbound emails sent or scheduled to the same recipient address in
      the given campaign since `since`. Used by the 24h dedupe guard.
      """

      argument :recipient_email, :string, allow_nil?: false
      argument :campaign_id, :uuid, allow_nil?: false
      argument :since, :utc_datetime_usec, allow_nil?: false

      filter expr(
               status in [:scheduled, :sent] and
                 thread.campaign_contact.campaign_id == ^arg(:campaign_id) and
                 thread.campaign_contact.person.email == ^arg(:recipient_email) and
                 inserted_at >= ^arg(:since)
             )
    end

    read :find_to_recipient_in_inbox do
      description """
      Latest sent/scheduled outbound from `email_account_id` whose joined
      contact.person.email matches `recipient_email`. Used to route an
      inbound bounce notification back to the originating send.
      """

      argument :email_account_id, :uuid, allow_nil?: false
      argument :recipient_email, :string, allow_nil?: false

      filter expr(
               email_account_id == ^arg(:email_account_id) and
                 status in [:sent, :scheduled] and
                 thread.campaign_contact.person.email == ^arg(:recipient_email)
             )

      prepare build(sort: [sent_at: :desc, inserted_at: :desc], limit: 1)
      get? true
    end

    read :list_user_edited_for_sequence do
      description """
      Few-shot examples for the AI writer, scoped to one template. Returns
      outbound rows whose contact was written under the given sequence and
      where the user edited the AI draft (user_subject or user_body
      non-nil), newest first, capped at limit. Empty pool ⇒ the writer
      produces a blank draft the user fills by hand.
      """

      argument :sequence_id, :uuid, allow_nil?: false
      argument :limit, :integer, allow_nil?: false

      filter expr(
               thread.campaign_contact.sequence_id == ^arg(:sequence_id) and
                 (not is_nil(user_subject) or not is_nil(user_body))
             )

      prepare build(sort: [inserted_at: :desc])
      prepare build(limit: arg(:limit))
    end

    read :list_halt_eligible_for_thread do
      description "Outbound rows to cancel on reply/halt: drafted + approved + scheduled."
      argument :thread_id, :uuid, allow_nil?: false

      filter expr(thread_id == ^arg(:thread_id) and status in [:drafted, :approved, :scheduled])
    end

    read :next_scheduled_for_thread do
      description """
      The thread's next pending send (status :scheduled), soonest first. Used
      to defer a sequence on an OOO auto-reply: only this one row needs its
      scheduled_at pushed out — later steps schedule lazily after each send.
      """

      argument :thread_id, :uuid, allow_nil?: false

      filter expr(thread_id == ^arg(:thread_id) and status == :scheduled)
      prepare build(sort: [scheduled_at: :asc], limit: 1)
      get? true
    end

    create :create_manual_reply do
      description """
      Persist a user-composed reply (rich-text from the thread composer)
      already sent through Nylas. step_position stays nil; is_manual_reply
      true; status :sent.
      """

      accept [
        :thread_id,
        :email_account_id,
        :user_subject,
        :user_body,
        :nylas_message_id,
        :nylas_thread_id,
        :sent_at
      ]

      change set_attribute(:status, :sent)
      change set_attribute(:is_manual_reply, true)
    end

    create :create_draft do
      description """
      Insert an AI-generated draft. Only ai_* is set; user_* stays nil
      unless the user edits. Effective subject/body is `user_? || ai_?`.
      """

      accept [
        :thread_id,
        :step_position,
        :ai_subject,
        :ai_body,
        :writer_meta
      ]

      change set_attribute(:status, :drafted)
      change set_attribute(:is_manual_reply, false)
    end

    update :update_user_fields do
      accept [:user_subject, :user_body]
      require_atomic? false
    end

    update :mark_approved do
      require_atomic? false
      change set_attribute(:status, :approved)
    end

    update :schedule do
      accept [:scheduled_at, :email_account_id]
      require_atomic? false
      change set_attribute(:status, :scheduled)
    end

    update :mark_sent do
      accept [:nylas_message_id, :nylas_thread_id, :sent_at]
      require_atomic? false
      change set_attribute(:status, :sent)
    end

    update :mark_bounced do
      accept [:bounce_reason]
      require_atomic? false
      change set_attribute(:status, :bounced)
    end

    update :mark_failed do
      require_atomic? false
      change set_attribute(:status, :failed)
    end

    update :mark_skipped do
      require_atomic? false
      change set_attribute(:status, :skipped)
    end

    update :update_tracking_counts do
      description "Sync open/click counts pulled from Nylas for one outbound message."
      accept [:opens_count, :clicks_count]
      require_atomic? false

      change fn changeset, _ ->
        Ash.Changeset.change_attribute(changeset, :tracking_synced_at, DateTime.utc_now())
      end
    end

    read :list_recent_for_tracking do
      description """
      Sent outbound rows that may have open/click activity to pull from
      Nylas. Filters to sends within the lookback window, in campaigns
      with at least one tracking toggle on.
      """

      argument :since, :utc_datetime_usec, allow_nil?: false

      filter expr(
               status == :sent and
                 sent_at >= ^arg(:since) and
                 not is_nil(nylas_message_id) and
                 (thread.campaign_contact.campaign.tracking_opens? == true or
                    thread.campaign_contact.campaign.tracking_clicks? == true)
             )

      prepare build(sort: [sent_at: :desc])
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

    policy action_type(:update) do
      authorize_if expr(thread.campaign_contact.campaign.owner_id == ^actor(:id))
    end

    policy action_type(:destroy) do
      authorize_if expr(thread.campaign_contact.campaign.owner_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :step_position, :integer, public?: true

    attribute :ai_subject, :string, public?: true
    attribute :ai_body, :string, public?: true
    attribute :user_subject, :string, public?: true
    attribute :user_body, :string, public?: true

    attribute :is_manual_reply, :boolean, allow_nil?: false, default: false, public?: true

    attribute :status, :atom,
      constraints: [
        one_of: [:drafted, :approved, :scheduled, :sent, :bounced, :failed, :skipped]
      ],
      allow_nil?: false,
      default: :drafted,
      public?: true

    attribute :scheduled_at, :utc_datetime_usec, public?: true
    attribute :sent_at, :utc_datetime_usec, public?: true

    attribute :nylas_message_id, :string, public?: true
    attribute :nylas_thread_id, :string, public?: true

    attribute :bounce_reason, :string, public?: true

    attribute :writer_meta, :map, public?: true, default: %{}

    attribute :opens_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :clicks_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :tracking_synced_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :thread, Colt.Resources.Thread, allow_nil?: false, public?: true

    belongs_to :email_account, Colt.Resources.EmailAccount,
      allow_nil?: true,
      public?: true
  end

  identities do
    identity :unique_nylas_message, [:nylas_message_id]
  end
end
