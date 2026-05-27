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
    define :recent_to_recipient, args: [:recipient_email, :campaign_id, :since]
    define :find_to_recipient_in_inbox, args: [:email_account_id, :recipient_email]
    define :list_halt_eligible_for_thread, args: [:thread_id]

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

    read :list_halt_eligible_for_thread do
      description "Outbound rows to cancel on reply/halt: drafted + scheduled."
      argument :thread_id, :uuid, allow_nil?: false

      filter expr(thread_id == ^arg(:thread_id) and status in [:drafted, :scheduled])
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

      accept [:thread_id, :step_position, :ai_subject, :ai_body]

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
