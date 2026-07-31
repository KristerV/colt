defmodule Colt.Repo.Migrations.CreateAbFunnelEvents do
  use Ecto.Migration

  def up, do: AbFunnel.Migrations.up()
  def down, do: AbFunnel.Migrations.down()
end
