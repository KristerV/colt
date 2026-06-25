defmodule Colt.Accounts do
  use Ash.Domain,
    otp_app: :colt

  resources do
    resource Colt.Accounts.Token

    resource Colt.Accounts.User do
      define :set_user_locale, action: :set_locale, args: [:locale]
      define :set_stripe_customer, args: [:stripe_customer_id]
      define :apply_subscription
      define :clear_subscription

      define :get_user_by_stripe_customer,
        action: :get_by_stripe_customer,
        args: [:stripe_customer_id]

      define :users_with_stripe_customer, action: :with_stripe_customer
      define :list_users, action: :read
    end
  end
end
