defmodule Colt.Resources.Campaign do
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "campaigns"
    repo Colt.Repo

    references do
      reference :owner, on_delete: :delete
    end
  end

  code_interface do
    define :create_draft, args: [:name]
    define :get, action: :read, get_by: [:id]
    define :set_icp, args: [:icp_description, :target_job_title, :business_model]
    define :set_market, args: [:market]
    define :list_recent_for_user, args: [:user_id]
    define :list_all_recent
    define :finalize, args: [:filters]
  end

  actions do
    defaults [:read]
    default_accept []

    read :list_recent_for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(owner_id == ^arg(:user_id))
      prepare build(sort: [inserted_at: :desc], limit: 4)
    end

    read :list_all_recent do
      description "Admin — every campaign across users, newest first."
      prepare build(sort: [inserted_at: :desc], limit: 200)
    end

    create :create_draft do
      description "Create a new draft campaign for the current user."
      accept [:name]
      change relate_actor(:owner)
      change set_attribute(:status, :draft)
    end

    update :set_icp do
      description "View 1 — set ICP description, target job title, and business model."
      accept [:icp_description, :target_job_title, :business_model]
      require_atomic? false
    end

    update :set_market do
      description "View 2 — set market and advance to :collecting (never downgrades)."
      accept [:market]
      change {Colt.Resources.Campaign.Changes.AdvanceStatus, to: :collecting}
      require_atomic? false
    end

    update :finalize do
      description "View 3 — save filters, lock the campaign, advance to :enriching (never downgrades)."
      accept [:filters]
      change {Colt.Resources.Campaign.Changes.AdvanceStatus, to: :enriching}

      change fn changeset, _ ->
        if Ash.Changeset.get_attribute(changeset, :finalized_at) do
          changeset
        else
          Ash.Changeset.change_attribute(changeset, :finalized_at, DateTime.utc_now())
        end
      end

      require_atomic? false
    end
  end

  policies do
    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(owner_id == ^actor(:id))
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:update) do
      authorize_if expr(owner_id == ^actor(:id))
    end

    policy action_type(:destroy) do
      authorize_if expr(owner_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :icp_description, :string, public?: true, constraints: [max_length: 2000]
    attribute :target_job_title, :string, public?: true

    attribute :business_model, :atom,
      constraints: [one_of: [:b2b, :b2c, :both]],
      default: :both,
      allow_nil?: false,
      public?: true

    attribute :market, :atom,
      constraints: [one_of: [:ee, :fi, :lv, :lt, :se, :no]],
      public?: true

    attribute :filters, :map, public?: true, default: %{}

    attribute :status, :atom,
      constraints: [one_of: [:draft, :collecting, :enriching, :complete, :archived]],
      allow_nil?: false,
      default: :draft,
      public?: true

    attribute :finalized_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :owner, Colt.Accounts.User, allow_nil?: false, public?: true
    has_many :campaign_companies, Colt.Resources.CampaignCompany
    has_many :api_calls, Colt.Resources.ApiCall
  end

  aggregates do
    count :total_count, :campaign_companies
    count :done_count, :campaign_companies, filter: expr(status == :enriched)
    sum :cost_usd, :api_calls, :cost_usd
  end
end
