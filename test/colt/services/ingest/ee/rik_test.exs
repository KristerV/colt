defmodule Colt.Services.Ingest.Ee.RikTest do
  @moduledoc """
  End-to-end test for the rik.ee Estonia ingest. Points the cache directory at
  the hand-crafted fixtures under `priv/fixtures/rik_ee/` so the test exercises
  every parsing branch the production pipeline runs.
  """

  use Colt.DataCase, async: false

  require Ash.Query

  alias Colt.Resources.{AnnualReport, Company}
  alias Colt.Services.Ingest.Ee.Rik

  @fixture_dir Path.join([:code.priv_dir(:colt), "fixtures", "rik_ee"])

  setup do
    prev = Application.get_env(:colt, :rik_ee_cache_dir)
    Application.put_env(:colt, :rik_ee_cache_dir, @fixture_dir)
    on_exit(fn -> Application.put_env(:colt, :rik_ee_cache_dir, prev) end)
    :ok
  end

  test "imports the fixture set end-to-end" do
    {:ok, summary} = Rik.run(from: 2)

    assert summary.companies.processed == 7
    assert summary.details.patched == 7
    assert summary.reports.years == [2022, 2023, 2024]

    companies =
      Company
      |> Ash.Query.sort(registry_code: :asc)
      |> Ash.read!()

    assert length(companies) == 7
    assert Enum.all?(companies, &(&1.market == :ee))

    by_code = Map.new(companies, &{&1.registry_code, &1})

    alpha = Map.fetch!(by_code, "10000001")
    assert alpha.name == "Alpha Growth OÜ"
    assert alpha.status == :registered
    assert alpha.website_url == "https://alpha.ee"
    assert alpha.website_source == :registry
    assert alpha.generic_email == "info@alpha.ee"
    assert alpha.industry_code == "62012"
    assert Decimal.equal?(alpha.revenue_latest, Decimal.new("600000.0"))
    assert alpha.employees_latest == 6
    assert alpha.revenue_growth_bucket == :slow

    beta = Map.fetch!(by_code, "10000002")
    assert beta.revenue_growth_bucket == :declining

    gamma = Map.fetch!(by_code, "10000003")
    assert gamma.revenue_growth_bucket == :stagnant

    delta = Map.fetch!(by_code, "10000004")
    assert delta.revenue_growth_bucket == :growing_10x
    assert is_nil(delta.generic_email)

    epsilon = Map.fetch!(by_code, "10000005")
    assert is_nil(epsilon.revenue_growth_bucket), "single-year company has no bucket"
    assert is_nil(epsilon.website_url)

    zeta = Map.fetch!(by_code, "10000006")
    assert zeta.status == :liquidation
    assert is_nil(zeta.revenue_growth_bucket), "liquidation report must be filtered out"

    eta = Map.fetch!(by_code, "10000007")
    assert eta.revenue_growth_bucket == :growing_2x

    eta_reports =
      AnnualReport.for_company!(eta.id)
      |> Map.new(&{&1.year, &1})

    assert Decimal.equal?(eta_reports[2023].revenue_eur, Decimal.new("1000000.0")),
           "report revision must win over the original filing"

    assert eta_reports[2023].employees == 15

    zeta_reports = AnnualReport.for_company!(zeta.id)
    assert zeta_reports == [], "no annual reports inserted for liquidation-only filings"
  end

  test "is idempotent on re-run" do
    {:ok, _} = Rik.run(from: 2)
    counts_before = {Ash.count!(Company), Ash.count!(AnnualReport)}

    {:ok, _} = Rik.run(from: 2)
    counts_after = {Ash.count!(Company), Ash.count!(AnnualReport)}

    assert counts_before == counts_after
  end

  test "company_details overrides on re-run" do
    {:ok, _} = Rik.run(from: 2)

    [alpha] = Ash.read!(Company |> Ash.Query.filter(registry_code == "10000001"))

    Ash.update!(alpha, %{website_url: "https://stale.example"}, action: :patch_details)

    {:ok, _} = Rik.run(from: 2)

    [alpha2] = Ash.read!(Company |> Ash.Query.filter(registry_code == "10000001"))
    assert alpha2.website_url == "https://alpha.ee"
  end
end
