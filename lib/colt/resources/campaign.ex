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
    define :list_for_user, args: [:user_id]
    define :list_all_recent
    define :rename, args: [:name]
    define :update_filters, args: [:filters]
    define :update_target, args: [:target_contact_count]
    define :finalize, args: [:target_contact_count]
    define :mark_sending_initialized
    define :set_tracking, args: [:tracking_opens?, :tracking_clicks?]
    define :set_panic, args: [:panic_switch_on]
    define :bump_auto_approve_streak
    define :set_auto_approve_on, args: [:auto_approve_on?]
  end

  actions do
    defaults [:read]
    default_accept []

    read :list_recent_for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(owner_id == ^arg(:user_id))
      prepare build(sort: [inserted_at: :desc], limit: 4)
    end

    read :list_for_user do
      description "Every campaign owned by the user, newest first."
      argument :user_id, :uuid, allow_nil?: false
      filter expr(owner_id == ^arg(:user_id))
      prepare build(sort: [inserted_at: :desc])
    end

    update :rename do
      description "Rename a campaign — works at any status."
      accept [:name]
      require_atomic? false
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

    update :update_filters do
      description "Persist filter selection without changing status. Used both before start and for mid-run edits."
      accept [:filters]
      require_atomic? false
    end

    update :update_target do
      description "Change target contact count without advancing status. Used for mid-run target edits."
      accept [:target_contact_count]
      change Colt.Resources.Campaign.Changes.CapacityGuard
      require_atomic? false
    end

    update :mark_sending_initialized do
      description "Flip sending_initialized? = true. Idempotent."
      accept []
      require_atomic? false
      change set_attribute(:sending_initialized?, true)
    end

    update :set_tracking do
      description "Toggle per-campaign open + click tracking."
      accept [:tracking_opens?, :tracking_clicks?]
      require_atomic? false
    end

    update :set_panic do
      description "Toggle the campaign-level panic switch."
      accept [:panic_switch_on]
      require_atomic? false
    end

    update :set_auto_approve_on do
      description "Flip auto_approve_on?. Caller should guard on auto_approve_unlocked?."
      accept [:auto_approve_on?]
      require_atomic? false
    end

    update :bump_auto_approve_streak do
      description """
      Increment auto_approve_streak by 1 on a clean approval (user did
      not edit any draft). At 10, unlock auto-approve.
      """

      accept []
      require_atomic? false

      change fn changeset, _ ->
        current = Ash.Changeset.get_attribute(changeset, :auto_approve_streak) || 0
        new = current + 1

        changeset
        |> Ash.Changeset.change_attribute(:auto_approve_streak, new)
        |> then(fn cs ->
          if new >= 10,
            do: Ash.Changeset.change_attribute(cs, :auto_approve_unlocked?, true),
            else: cs
        end)
      end
    end

    update :finalize do
      description "Start enrichment — set target contact count, advance to :enriching (never downgrades), stamp finalized_at."
      accept [:target_contact_count]
      change Colt.Resources.Campaign.Changes.CapacityGuard
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

    attribute :target_contact_count, :integer,
      public?: true,
      default: 100,
      allow_nil?: false,
      constraints: [min: 1]

    attribute :status, :atom,
      constraints: [one_of: [:draft, :collecting, :enriching, :archived]],
      allow_nil?: false,
      default: :draft,
      public?: true

    attribute :finalized_at, :utc_datetime_usec, public?: true

    attribute :sending_initialized?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :panic_switch_on, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :auto_approve_unlocked?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :auto_approve_on?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :auto_approve_streak, :integer,
      allow_nil?: false,
      default: 0,
      public?: true,
      constraints: [min: 0]

    attribute :tracking_opens?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :tracking_clicks?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :owner, Colt.Accounts.User, allow_nil?: false, public?: true
    has_many :campaign_companies, Colt.Resources.CampaignCompany
    has_many :api_calls, Colt.Resources.ApiCall
    has_many :campaign_email_accounts, Colt.Resources.CampaignEmailAccount
    has_one :sequence, Colt.Resources.Sequence
  end

  aggregates do
    count :total_count, :campaign_companies
    count :done_count, :campaign_companies, filter: expr(status == :enriched)
    sum :cost_usd, :api_calls, :cost_usd
  end
end
