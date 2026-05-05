defmodule Colt.Domain do
  use Ash.Domain,
    otp_app: :colt

  resources do
    resource Colt.Resources.Company
    resource Colt.Resources.AnnualReport
  end
end
