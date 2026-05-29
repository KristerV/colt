defmodule Colt.Services.Ingest.No.Brreg.GrowthRollup do
  @moduledoc """
  Reuses `Colt.Services.Ingest.Ee.Rik.GrowthRollup.run/0` — the SQL is
  market-agnostic (joins `annual_reports` to `companies` by `company_id`),
  so it correctly projects NO rows onto `companies.{revenue_latest,
  employees_latest, revenue_growth_bucket}` alongside every other market.

  Same pattern as `Colt.Services.Ingest.Lv.Ur.GrowthRollup`.
  """

  defdelegate run, to: Colt.Services.Ingest.Ee.Rik.GrowthRollup
end
