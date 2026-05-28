defmodule Colt.Accounts do
  use Ash.Domain,
    otp_app: :colt

  resources do
    resource Colt.Accounts.Token

    resource Colt.Accounts.User do
      define :set_user_locale, action: :set_locale, args: [:locale]
    end
  end
end
