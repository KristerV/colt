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
    # Rik.run wipes the cache dir once an ingest succeeds, so point the cache at
    # a tmp copy of the fixtures (the originals survive) and re-seed it before
    # every `from: 2` run that follows a successful one.
    tmp =
      Path.join(System.tmp_dir!(), "rik_ee_fixtures_#{System.unique_integer([:positive])}")

    seed_cache(tmp)

    prev = Application.get_env(:colt, :rik_ee_cache_dir)
    Application.put_env(:colt, :rik_ee_cache_dir, tmp)

    on_exit(fn ->
      Application.put_env(:colt, :rik_ee_cache_dir, prev)
      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  # Copy the fixture files into the cache dir. `Rik.run` deletes them on success,
  # so callers that re-run the ingest must seed again first.
  defp seed_cache(tmp) do
    File.mkdir_p!(tmp)

    for name <- File.ls!(@fixture_dir) do
      File.cp!(Path.join(@fixture_dir, name), Path.join(tmp, name))
    end
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
    # The registry EMAIL contact-means lands in :registry_email, never
    # :generic_email — the latter is reserved for what the landing scrape finds.
    assert alpha.registry_email == "info@alpha.ee"
    assert alpha.generic_email == nil
    # Not classified at import: that costs a model call per company, and only
    # companies that actually enter a funnel are worth spending it on.
    assert alpha.registry_email_kind == nil
    # EMTAK 2008 (62011) forward-translated to its EMTAK 2025 equivalent.
    assert alpha.industry_code == "62101"
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

  # RIK serves EMTAK 2008 and EMTAK 2025 side by side — a company keeps its old code
  # until it re-declares — and we store Rev 2.1 only. See Colt.Filters.NaceMigration.
  test "forward-translates EMTAK 2008 codes and passes EMTAK 2025 through" do
    {:ok, _} = Rik.run(from: 2)

    by_code =
      Company
      |> Ash.Query.filter(market == :ee)
      |> Ash.read!()
      |> Map.new(&{&1.registry_code, &1})

    # EMTAK 2025 rows are already Rev 2.1 and must not be rewritten.
    assert by_code["10000002"].industry_code == "62101"
    assert by_code["10000005"].industry_code == "96211"

    # A class that survived the revision unchanged keeps its code.
    assert by_code["10000003"].industry_code == "73111"

    # The case that started all this: EMTAK 2008 45201 (motor vehicle repair) has no
    # division 45 in Rev 2.1 — it becomes 95311, so LEFT(code, 4) filters as 9531.
    assert by_code["10000004"].industry_code == "95311"
    assert String.slice(by_code["10000004"].industry_code, 0, 4) == "9531"

    # 47911 "retail via mail order or internet" dissolved across 44 Rev 2.1 classes;
    # we drop the code rather than fabricate one. The company survives, unlabelled.
    assert is_nil(by_code["10000007"].industry_code)
    assert by_code["10000007"].name == "Eta Big OÜ"
  end

  test "is idempotent on re-run", %{tmp: tmp} do
    {:ok, _} = Rik.run(from: 2)
    counts_before = {Ash.count!(Company), Ash.count!(AnnualReport)}

    seed_cache(tmp)
    {:ok, _} = Rik.run(from: 2)
    counts_after = {Ash.count!(Company), Ash.count!(AnnualReport)}

    assert counts_before == counts_after
  end

  test "company_details overrides on re-run", %{tmp: tmp} do
    {:ok, _} = Rik.run(from: 2)

    [alpha] = Ash.read!(Company |> Ash.Query.filter(registry_code == "10000001"))

    Ash.update!(alpha, %{website_url: "https://stale.example"}, action: :patch_details)

    seed_cache(tmp)
    {:ok, _} = Rik.run(from: 2)

    [alpha2] = Ash.read!(Company |> Ash.Query.filter(registry_code == "10000001"))
    assert alpha2.website_url == "https://alpha.ee"
  end
end
