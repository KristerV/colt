defmodule Colt.Accounts do
  use Ash.Domain,
    otp_app: :colt

  resources do
    resource Colt.Accounts.Token
    resource Colt.Accounts.User
  end
end
