defmodule Colt.Repo.Migrations.AddAbFunnelEventAssignments do
  use Ecto.Migration

  # Events now carry a bucket per experiment instead of one `variant` column.
  #
  # The truncate is deliberate and is the reason this is safe to do in one step.
  # Every row predating this migration was written without an entry gate, so the
  # table holds people who never opened the deck alongside a handful of test runs
  # of ours — the "200% step conversion" data. Backfilling `assignments` from
  # `variant` would carry that forward under a schema that implies it was
  # measured properly. Starting empty is the honest option, and `/admin/ab` is
  # the only reader.
  def up do
    AbFunnel.Migrations.add_event_assignments()

    execute("TRUNCATE TABLE ab_funnel_events")
    execute("TRUNCATE TABLE ab_funnel_identities")
  end

  # No inverse for the truncate — the rows are gone either way.
  def down, do: AbFunnel.Migrations.drop_event_assignments()
end
