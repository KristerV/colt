defmodule Colt.Resources.EmailAccount do
  @moduledoc """
  One connected inbox per user. Nylas v3 holds the OAuth tokens; we only
  store the `nylas_grant_id`. Sending and polling scope by this row.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "email_accounts"
    repo Colt.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :get_by_grant, args: [:nylas_grant_id]
    define :list_for_user, args: [:user_id]
    define :list_all
    define :list_healthy

    define :create_from_nylas,
      args: [:provider, :address, :display_name, :nylas_grant_id, :tz]

    define :mark_status, args: [:status, :paused_reason]
    define :touch_sync, args: [:last_sync_at]
    define :disconnect
    define :set_quota, args: [:daily_quota]
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    read :get_by_grant do
      argument :nylas_grant_id, :string, allow_nil?: false
      filter expr(nylas_grant_id == ^arg(:nylas_grant_id))
      get? true
    end

    read :list_for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
      prepare build(sort: [inserted_at: :desc])
    end

    read :list_all do
      description "Admin — every connected inbox across users."
      prepare build(sort: [inserted_at: :desc])
    end

    read :list_healthy do
      description "Connected, sendable inboxes — used by the inbound poller."
      filter expr(status == :healthy and not is_nil(nylas_grant_id))
      prepare build(sort: [inserted_at: :asc])
    end

    create :create_from_nylas do
      description "Called from /email-accounts/callback after Nylas hosted auth."
      accept [:provider, :address, :display_name, :nylas_grant_id, :tz]
      upsert? true
      upsert_identity :nylas_grant
      upsert_fields [:provider, :address, :display_name, :tz, :status, :paused_reason]
      change relate_actor(:user)
      change set_attribute(:status, :healthy)
      change set_attribute(:paused_reason, nil)
    end

    update :mark_status do
      accept [:status, :paused_reason]
      require_atomic? false
    end

    update :touch_sync do
      accept [:last_sync_at]
      require_atomic? false
    end

    update :disconnect do
      description "Set status :disconnected. Caller is expected to revoke at Nylas first."
      accept []
      require_atomic? false
      change set_attribute(:status, :disconnected)
    end

    update :set_quota do
      description "Set the global daily send ceiling for this inbox."
      accept [:daily_quota]
      require_atomic? false
    end
  end

  policies do
    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:update) do
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action_type(:destroy) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom,
      constraints: [one_of: [:google, :m365, :imap]],
      allow_nil?: false,
      public?: true

    attribute :address, :string, allow_nil?: false, public?: true
    attribute :display_name, :string, public?: true

    attribute :nylas_grant_id, :string, public?: true

    attribute :tz, :string,
      allow_nil?: false,
      default: "Europe/Tallinn",
      public?: true

    attribute :daily_quota, :integer,
      allow_nil?: false,
      default: 15,
      public?: true,
      constraints: [min: 0]

    attribute :status, :atom,
      constraints: [one_of: [:healthy, :paused_bounces, :disconnected, :auth_error]],
      allow_nil?: false,
      default: :healthy,
      public?: true

    attribute :last_sync_at, :utc_datetime_usec, public?: true
    attribute :paused_reason, :string, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Colt.Accounts.User, allow_nil?: false, public?: true
    has_many :campaign_email_accounts, Colt.Resources.CampaignEmailAccount
  end

  identities do
    identity :nylas_grant, [:nylas_grant_id]
  end
end
