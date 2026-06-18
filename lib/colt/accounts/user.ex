defmodule Colt.Accounts.User do
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

    tokens do
      enabled? true
      token_resource Colt.Accounts.Token
      signing_secret Colt.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
      token_lifetime {90, :days}
    end

    strategies do
      magic_link do
        identity_field :email
        registration_enabled? true
        require_interaction? true

        sender Colt.Accounts.User.Senders.SendMagicLinkEmail
      end

      remember_me :remember_me
    end
  end

  postgres do
    table "users"
    repo Colt.Repo
  end

  actions do
    defaults [:read]

    update :set_locale do
      accept [:locale]
      require_atomic? true
    end

    update :set_stripe_customer do
      description "Persist the Stripe customer id after first checkout."
      accept [:stripe_customer_id]
      require_atomic? false
    end

    update :apply_subscription do
      description "Webhook → apply current subscription state (capacity + period bounds + status)."

      accept [
        :monthly_contact_capacity,
        :subscription_period_start,
        :subscription_period_end,
        :subscription_status
      ]

      require_atomic? false
    end

    update :clear_subscription do
      description "Webhook → subscription canceled; zero capacity, mark canceled."
      accept []
      change set_attribute(:monthly_contact_capacity, 0)
      change set_attribute(:subscription_status, :canceled)
      require_atomic? false
    end

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    read :get_by_stripe_customer do
      description "Webhook lookup by Stripe customer id."
      argument :stripe_customer_id, :string, allow_nil?: false
      get? true
      filter expr(stripe_customer_id == ^arg(:stripe_customer_id))
    end

    create :sign_in_with_magic_link do
      description "Sign in or register a user with magic link."

      argument :token, :string do
        description "The token from the magic link that was sent to the user"
        allow_nil? false
      end

      argument :remember_me, :boolean do
        description "Whether to generate a remember me token"
        allow_nil? true
      end

      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email]

      # Uses the information from the token to create or sign in the user
      change AshAuthentication.Strategy.MagicLink.SignInChange

      change {AshAuthentication.Strategy.RememberMe.MaybeGenerateTokenChange,
              strategy_name: :remember_me}

      change Colt.Accounts.User.Changes.MaybePromoteFirstAdmin
      change Colt.Accounts.User.Changes.NotifyNewUser

      metadata :token, :string do
        allow_nil? false
      end
    end

    create :seed do
      description "Seeds / tests only. Skips magic-link plumbing but applies the first-admin rule."
      accept [:email]
      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email]
      change Colt.Accounts.User.Changes.MaybePromoteFirstAdmin
    end

    action :request_magic_link do
      argument :email, :ci_string do
        allow_nil? false
      end

      run AshAuthentication.Strategy.MagicLink.Request
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(^actor(:is_admin) == true)
      authorize_if expr(id == ^actor(:id))
    end

    policy action(:set_locale) do
      authorize_if expr(id == ^actor(:id))
    end

    policy action([:set_stripe_customer, :apply_subscription, :clear_subscription]) do
      authorize_if expr(id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :is_admin, :boolean do
      allow_nil? false
      default false
      public? false
    end

    attribute :locale, :string do
      public? true
      allow_nil? true
    end

    attribute :stripe_customer_id, :string do
      public? false
      allow_nil? true
    end

    attribute :monthly_contact_capacity, :integer do
      public? true
      allow_nil? false
      default 0
      constraints min: 0
    end

    attribute :subscription_period_start, :utc_datetime do
      public? true
      allow_nil? true
    end

    attribute :subscription_period_end, :utc_datetime do
      public? true
      allow_nil? true
    end

    attribute :subscription_status, :atom do
      public? true
      allow_nil? false
      default :none
      constraints one_of: [:none, :active, :past_due, :canceled]
    end

    # Registration time. Backfilled to the migration moment for users that
    # predate this column; accurate for everyone who signs up after.
    timestamps()
  end

  relationships do
    has_many :campaigns, Colt.Resources.Campaign, destination_attribute: :owner_id
  end

  calculations do
    # Contacts delivered vs. the plan's monthly contact cap.
    calculate :remaining_capacity,
              :integer,
              expr(monthly_contact_capacity - enriched_this_period_count)

    # Screening allowance is derived: 20 companies screened per contact of cap
    # (the 20:1 pricing guardrail). Not stored — the contact cap is the single
    # source of truth.
    calculate :monthly_screening_capacity,
              :integer,
              expr(monthly_contact_capacity * 20)

    calculate :remaining_screening,
              :integer,
              expr(monthly_contact_capacity * 20 - screened_this_period_count)
  end

  aggregates do
    count :enriched_this_period_count, [:campaigns, :campaign_companies] do
      filter expr(
               status == :enriched and
                 inserted_at >= parent(subscription_period_start)
             )
    end

    # "Screenings used" = companies we fully evaluated against ICP this period
    # (fit or not), excluding dead scrapes (no_website / failed), which are free.
    count :screened_this_period_count, [:campaigns, :campaign_companies] do
      filter expr(
               status in [:rejected, :no_contacts, :verify_failed, :enriched] and
                 inserted_at >= parent(subscription_period_start)
             )
    end

    count :campaigns_count, :campaigns
  end

  identities do
    identity :unique_email, [:email]
  end

  @doc """
  Whether the user may use the paid features — the gate for the
  enrichment-trigger and sending features. An exhausted-but-active user is
  still `paid?` (they keep app access; Topup just stops admitting work).

  Admins bypass the paywall entirely: they never need to buy a package.
  """
  def paid?(%{is_admin: true}), do: true

  def paid?(%{subscription_status: :active, monthly_contact_capacity: cap})
      when is_integer(cap) and cap > 0,
      do: true

  def paid?(_), do: false
end
