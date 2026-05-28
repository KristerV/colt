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
  end

  identities do
    identity :unique_email, [:email]
  end
end
