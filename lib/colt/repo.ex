defmodule Colt.Repo do
  use Ecto.Repo,
    otp_app: :colt,
    adapter: Ecto.Adapters.Postgres
end
