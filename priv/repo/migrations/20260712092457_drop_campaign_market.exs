defmodule Colt.Repo.Migrations.DropCampaignMarket do
  @moduledoc """
  Drops the legacy single-market `campaigns.market` column. Markets now live in
  the `filters` jsonb as `filters["markets"]` (an array). Before dropping, this
  backfills any campaign that still relies on `market` into the new format.
  """

  use Ecto.Migration

  def up do
    # Backfill legacy single market → filters["markets"] = ["<market>"], but only
    # for campaigns that don't already carry the new multi-market list.
    execute("""
    UPDATE campaigns
    SET filters = jsonb_set(COALESCE(filters, '{}'::jsonb), '{markets}', to_jsonb(ARRAY[market::text]))
    WHERE market IS NOT NULL
      AND (filters -> 'markets') IS NULL
    """)

    alter table(:campaigns) do
      remove :market
    end
  end

  def down do
    alter table(:campaigns) do
      add :market, :text
    end

    # Best-effort restore: take the first market from the new list.
    execute("""
    UPDATE campaigns
    SET market = (filters -> 'markets' ->> 0)
    WHERE (filters -> 'markets' ->> 0) IS NOT NULL
    """)
  end
end
