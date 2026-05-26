defmodule Colt.Resources.CampaignEmailAccount do
  @moduledoc """
  Enrollment of an `EmailAccount` into a `Campaign`. Quota lives globally on
  `EmailAccount.daily_quota` — this row only tracks per-campaign pause state.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "campaign_email_accounts"
    repo Colt.Repo

    references do
      reference :campaign, on_delete: :delete
      reference :email_account, on_delete: :delete
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :list_for_campaign, args: [:campaign_id]
    define :get_pairing, args: [:campaign_id, :email_account_id]
    define :enroll, args: [:campaign_id, :email_account_id]
    define :remove
    define :pause, args: [:paused_reason]
    define :unpause
  end

  actions do
    defaults [:read]
    default_accept []

    read :list_for_campaign do
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id))
      prepare build(sort: [inserted_at: :asc])
    end

    read :get_pairing do
      description "Lookup the enrollment row for a (campaign, email_account) pair."
      argument :campaign_id, :uuid, allow_nil?: false
      argument :email_account_id, :uuid, allow_nil?: false

      filter expr(
               campaign_id == ^arg(:campaign_id) and
                 email_account_id == ^arg(:email_account_id)
             )

      get? true
    end

    create :enroll do
      description "Add an EmailAccount to a Campaign. Idempotent via the unique identity."
      accept [:campaign_id, :email_account_id]
      upsert? true
      upsert_identity :unique_per_campaign
    end

    destroy :remove do
      require_atomic? false
    end

    update :pause do
      accept [:paused_reason]
      require_atomic? false
      change set_attribute(:paused?, true)
    end

    update :unpause do
      accept []
      require_atomic? false
      change set_attribute(:paused?, false)
      change set_attribute(:paused_reason, nil)
    end
  end

  policies do
    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(campaign.owner_id == ^actor(:id))
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:update) do
      authorize_if expr(campaign.owner_id == ^actor(:id))
    end

    policy action_type(:destroy) do
      authorize_if expr(campaign.owner_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :paused?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :paused_reason, :string, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign, Colt.Resources.Campaign, allow_nil?: false, public?: true
    belongs_to :email_account, Colt.Resources.EmailAccount, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_per_campaign, [:campaign_id, :email_account_id]
  end
end
