defmodule Colt.Repo.Migrations.CreateAbFunnelEvents do
  use Ecto.Migration

  # Deliberately `create_events/0` and not `up/0`: the library's `up/0` grew to create the
  # identities table too, and this migration has already run everywhere. Left as `up/0` it
  # would create identities on a fresh database — CI, `mix ecto.reset` — and the later
  # identities migration would then die on `duplicate_table`.
  def up, do: AbFunnel.Migrations.create_events()
  def down, do: AbFunnel.Migrations.drop_events()
end
