defmodule Colt.Repo.Migrations.AddAbFunnelIdentities do
  use Ecto.Migration

  # Binds a browser to a person, so someone who plays the deck on their phone and clicks
  # the magic link on their laptop is one journey in the funnel rather than two.
  #
  # The time index is folded in here rather than left for later: nothing queries by time
  # yet, but `ab_funnel_events` only grows, so indexing it is cheapest today. It is
  # `create_if_not_exists` in the library — on a fresh database the events migration has
  # already made it, and this has to be a no-op rather than an error.
  def up do
    AbFunnel.Migrations.create_identities()
    AbFunnel.Migrations.create_event_time_index()
  end

  def down do
    AbFunnel.Migrations.drop_event_time_index()
    AbFunnel.Migrations.drop_identities()
  end
end
