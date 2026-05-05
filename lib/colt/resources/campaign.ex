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
    define :set_icp, args: [:icp_description, :target_job_title]
    define :set_market, args: [:market]
    define :list_recent_for_user, args: [:user_id]
  end

  actions do
    defaults [:read]
    default_accept []

    read :list_recent_for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(owner_id == ^arg(:user_id))
      prepare build(sort: [inserted_at: :desc], limit: 4)
    end

    create :create_draft do
      description "Create a new draft campaign for the current user."
      accept [:name]
      change relate_actor(:owner)
      change set_attribute(:status, :draft)
    end

    update :set_icp do
      description "View 1 — set ICP description and target job title."
      accept [:icp_description, :target_job_title]
      require_atomic? false
    end

    update :set_market do
      description "View 2 — set market and advance to :collecting."
      accept [:market]
      change set_attribute(:status, :collecting)
      require_atomic? false
    end
  end

  policies do
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
  end

  aggregates do
    count :total_count, :campaign_companies
    count :done_count, :campaign_companies, filter: expr(status == :enriched)
  end
end
