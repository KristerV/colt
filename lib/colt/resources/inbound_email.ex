defmodule Colt.Resources.InboundEmail do
  @moduledoc """
  One inbound message attached to a Thread. Created by the polling
  worker (`Colt.Services.Sending.IngestInbound`). Bounce notifications
  do NOT land here — they flip the originating OutboundEmail to
  `:bounced` and never reach the thread timeline.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "inbound_emails"
    repo Colt.Repo

    references do
      reference :thread, on_delete: :delete
      reference :email_account, on_delete: :nilify
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :find_by_nylas_message, args: [:nylas_message_id]
    define :list_for_thread, args: [:thread_id]

    define :create_inbound,
      args: [
        :thread_id,
        :email_account_id,
        :from_address,
        :subject,
        :body,
        :nylas_message_id,
        :nylas_thread_id,
        :received_at,
        :auto_attached?
      ]

    define :set_reply_category, args: [:reply_category]
    define :interested_by_month, args: [:months_back]
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    read :find_by_nylas_message do
      description "Idempotency check for inbound polling."
      argument :nylas_message_id, :string, allow_nil?: false
      filter expr(nylas_message_id == ^arg(:nylas_message_id))
      get? true
    end

    read :list_for_thread do
      argument :thread_id, :uuid, allow_nil?: false
      filter expr(thread_id == ^arg(:thread_id))
      prepare build(sort: [received_at: :asc])
    end

    # Contacts that went interested, per owner per month — the last column of
    # the admin client view. Returns {:ok, [%{user_id, month, count}]}.
    action :interested_by_month, {:array, :map} do
      argument :months_back, :integer, default: 12

      run fn input, _ctx ->
        interested_by_month_rows(input.arguments.months_back)
      end
    end

    create :create_inbound do
      description """
      Insert (or upsert) an inbound message. `received_at` is the Nylas
      message date. `auto_attached?` is true when we matched by sender
      domain rather than `nylas_thread_id`.
      """

      accept [
        :thread_id,
        :email_account_id,
        :from_address,
        :subject,
        :body,
        :nylas_message_id,
        :nylas_thread_id,
        :received_at,
        :auto_attached?
      ]

      upsert? true
      upsert_identity :unique_nylas_message
    end

    update :set_reply_category do
      accept [:reply_category]
      require_atomic? false
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

    attribute :from_address, :string, allow_nil?: false, public?: true
    attribute :subject, :string, public?: true
    attribute :body, :string, public?: true

    attribute :received_at, :utc_datetime_usec, allow_nil?: false, public?: true

    attribute :nylas_message_id, :string, public?: true
    attribute :nylas_thread_id, :string, public?: true

    attribute :reply_category, :atom,
      constraints: [one_of: [:ooo, :interested, :not_interested, :other]],
      public?: true

    attribute :auto_attached?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

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

  @doc false
  # Distinct contacts whose reply was categorised :interested, per owner per
  # "YYYY-MM" month. Dated off the reply's `received_at` — an immutable stamp,
  # unlike the contact row's updated_at, so a month's count never drifts.
  # Returns {:ok, [%{user_id, month, count}]}.
  def interested_by_month_rows(months_back) when is_integer(months_back) and months_back > 0 do
    import Ecto.Query

    cutoff = DateTime.add(DateTime.utc_now(), -months_back * 31 * 86_400, :second)

    rows =
      from(ie in "inbound_emails",
        join: t in "threads",
        on: t.id == ie.thread_id,
        join: cc in "campaign_contacts",
        on: cc.id == t.campaign_contact_id,
        join: camp in "campaigns",
        on: camp.id == cc.campaign_id,
        where: ie.reply_category == "interested" and ie.received_at >= ^cutoff,
        group_by: [
          fragment("?::text", camp.owner_id),
          fragment("to_char(?, 'YYYY-MM')", ie.received_at)
        ],
        select: %{
          user_id: fragment("?::text", camp.owner_id),
          month: fragment("to_char(?, 'YYYY-MM')", ie.received_at),
          count: fragment("count(distinct ?)", cc.id)
        }
      )
      |> Colt.Repo.all()

    {:ok, rows}
  end
end
