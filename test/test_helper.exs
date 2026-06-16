# `:eval` tests hit the live model and are excluded by default. Run them with
# `mix test --only eval`.
ExUnit.start(exclude: [:eval])
Ecto.Adapters.SQL.Sandbox.mode(Colt.Repo, :manual)
