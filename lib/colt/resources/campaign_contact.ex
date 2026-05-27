defmodule Colt.Resources.CampaignContact do
  @moduledoc """
  Join row between a Campaign and a Person (the picked contact for a
  CampaignCompany). Carries per-contact sending state: status, sticky
  inbox assignment, frozen sequence snapshot, reply category.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "campaign_contacts"
    repo Colt.Repo

    references do
      reference :campaign, on_delete: :delete
      reference :person, on_delete: :delete
      reference :assigned_email_account, on_delete: :nilify
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :list_for_campaign, args: [:campaign_id]
    define :next_pending, args: [:campaign_id]
    define :promote, args: [:campaign_id, :person_id]
    define :approve, args: [:assigned_email_account_id, :sequence_snapshot, :sequence_version]
    define :skip
    define :mark_replied, args: [:reply_category]
    define :mark_bounced
    define :mark_failed
    define :set_status, args: [:status]
    define :count_assigned_today, args: [:email_account_id]
    define :find_active_in_inbox_by_domain, args: [:email_account_id, :domain_suffix]
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    read :list_for_campaign do
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id))
      prepare build(sort: [inserted_at: :asc])
    end

    read :next_pending do
      description "Oldest contact in :pending_approval for a campaign."
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id) and status == :pending_approval)
      prepare build(sort: [inserted_at: :asc], limit: 1)
      get? true
    end

    create :promote do
      description """
      Insert a CampaignContact in :pending_approval for the given
      (campaign, person). Idempotent via the unique identity.
      """

      accept [:campaign_id, :person_id]
      upsert? true
      upsert_identity :unique_per_campaign
    end

    update :approve do
      description """
      Mark contact as approved. Stores the sequence snapshot + version
      and the sticky inbox. Sets approved_at = now.
      """

      accept [:assigned_email_account_id, :sequence_snapshot, :sequence_version]
      require_atomic? false

      change set_attribute(:status, :approved)

      change fn changeset, _ ->
        Ash.Changeset.change_attribute(changeset, :approved_at, DateTime.utc_now())
      end
    end

    update :skip do
      require_atomic? false
      change set_attribute(:status, :no_reply)

      change fn changeset, _ ->
        Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())
      end
    end

    update :mark_replied do
      accept [:reply_category]
      require_atomic? false
      change set_attribute(:status, :replied)
    end

    update :mark_bounced do
      require_atomic? false
      change set_attribute(:status, :bounced)
    end

    update :mark_failed do
      require_atomic? false
      change set_attribute(:status, :failed)
    end

    update :set_status do
      accept [:status]
      require_atomic? false
    end

    read :find_active_in_inbox_by_domain do
      description """
      Cross-domain reply fallback (§1.9/§7.2.4). Latest in-flight contact
      assigned to this inbox whose person email ends in @domain_suffix.
      Excludes terminal statuses.
      """

      argument :email_account_id, :uuid, allow_nil?: false
      argument :domain_suffix, :string, allow_nil?: false

      filter expr(
               assigned_email_account_id == ^arg(:email_account_id) and
                 status in [:approved, :sending] and
                 fragment("lower(?) like '%@' || lower(?)", person.email, ^arg(:domain_suffix))
             )

      prepare build(sort: [updated_at: :desc], limit: 1)
      get? true
    end

    read :count_assigned_today do
      description """
      Number of CampaignContacts approved-and-assigned to the given inbox
      today (UTC date). Used by the sticky-inbox picker.
      """

      argument :email_account_id, :uuid, allow_nil?: false

      filter expr(
               assigned_email_account_id == ^arg(:email_account_id) and
                 fragment("(?)::date = (now() at time zone 'utc')::date", approved_at)
             )
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

    attribute :status, :atom,
      constraints: [
        one_of: [
          :pending_approval,
          :approved,
          :sending,
          :replied,
          :call_ready,
          :no_reply,
          :bounced,
          :failed
        ]
      ],
      allow_nil?: false,
      default: :pending_approval,
      public?: true

    attribute :sequence_snapshot, :map, public?: true
    attribute :sequence_version, :integer, public?: true

    attribute :reply_category, :atom,
      constraints: [one_of: [:ooo, :interested, :not_interested, :other]],
      public?: true

    attribute :auto_approved?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :approved_at, :utc_datetime_usec, public?: true
    attribute :completed_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign, Colt.Resources.Campaign, allow_nil?: false, public?: true
    belongs_to :person, Colt.Resources.Person, allow_nil?: false, public?: true

    belongs_to :assigned_email_account, Colt.Resources.EmailAccount,
      allow_nil?: true,
      public?: true

    has_one :thread, Colt.Resources.Thread
  end

  identities do
    identity :unique_per_campaign, [:campaign_id, :person_id]
  end
end
