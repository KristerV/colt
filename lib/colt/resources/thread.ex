defmodule Colt.Resources.Thread do
  @moduledoc """
  One Thread per CampaignContact in v1. Container for outbound + inbound
  Emails and free-form Notes. `nylas_thread_id` is null until the first
  send returns one.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "threads"
    repo Colt.Repo

    references do
      reference :campaign_contact, on_delete: :delete
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :for_contact, args: [:campaign_contact_id]
    define :find_by_nylas_thread_id, args: [:nylas_thread_id]
    define :create_for_contact, args: [:campaign_contact_id]
    define :set_nylas_thread_id, args: [:nylas_thread_id]
    define :touch_activity, args: [:last_activity_at]
    define :set_manual_status_override, args: [:manual_status_override]
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    read :for_contact do
      argument :campaign_contact_id, :uuid, allow_nil?: false
      filter expr(campaign_contact_id == ^arg(:campaign_contact_id))
      get? true
    end

    read :find_by_nylas_thread_id do
      argument :nylas_thread_id, :string, allow_nil?: false
      filter expr(nylas_thread_id == ^arg(:nylas_thread_id))
      get? true
    end

    create :create_for_contact do
      accept [:campaign_contact_id]
      upsert? true
      upsert_identity :one_per_contact
    end

    update :set_nylas_thread_id do
      accept [:nylas_thread_id]
      require_atomic? false
    end

    update :touch_activity do
      accept [:last_activity_at]
      require_atomic? false
    end

    update :set_manual_status_override do
      accept [:manual_status_override]
      require_atomic? false
    end
  end

  policies do
    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(campaign_contact.campaign.owner_id == ^actor(:id))
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:update) do
      authorize_if expr(campaign_contact.campaign.owner_id == ^actor(:id))
    end

    policy action_type(:destroy) do
      authorize_if expr(campaign_contact.campaign.owner_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :nylas_thread_id, :string, public?: true
    attribute :last_activity_at, :utc_datetime_usec, public?: true
    attribute :manual_status_override, :string, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign_contact, Colt.Resources.CampaignContact,
      allow_nil?: false,
      public?: true

    has_many :outbound_emails, Colt.Resources.OutboundEmail
    has_many :inbound_emails, Colt.Resources.InboundEmail
    has_many :notes, Colt.Resources.Note
    has_many :status_events, Colt.Resources.StatusEvent
  end

  identities do
    identity :one_per_contact, [:campaign_contact_id]
  end
end
