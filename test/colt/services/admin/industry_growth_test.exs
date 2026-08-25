defmodule Colt.Services.Admin.IndustryGrowthTest do
  use Colt.DataCase, async: false

  alias Colt.Resources.{AnnualReport, Company}
  alias Colt.Services.Admin.IndustryGrowth

  # 62.10 is "Computer programming activities" — group 621, division 62,
  # section K. 10.11 is meat processing — group 101, division 10, section C.
  @programming "6210"
  @meat "1011"

  setup do
    {base_year, latest_year} = IndustryGrowth.year_pair()
    %{base_year: base_year, latest_year: latest_year}
  end

  defp company(industry_code, opts \\ []) do
    market = Keyword.get(opts, :market, :ee)

    Company.upsert_full!(
      %{
        registry_code: "c#{System.unique_integer([:positive])}",
        market: market,
        name: "co",
        status: :registered,
        industry_code: industry_code
      },
      authorize?: false
    )
  end

  defp report(company, year, revenue) do
    AnnualReport.upsert!(
      %{company_id: company.id, year: year, revenue_eur: revenue, source: :rik},
      authorize?: false
    )
  end

  # `n` companies in `code` going `base` → `latest` euros in the compared years.
  defp seed(code, n, base, latest, ctx, opts \\ []) do
    for _ <- 1..n do
      c = company(code, opts)
      if base, do: report(c, ctx.base_year, base)
      if latest, do: report(c, ctx.latest_year, latest)
      c
    end
  end

  describe "year_pair/0" do
    test "compares last calendar year against the one before it" do
      {base_year, latest_year} = IndustryGrowth.year_pair()

      assert latest_year == Date.utc_today().year - 1
      assert base_year == latest_year - 1
    end
  end

  describe "load/1" do
    test "totals and medians roll up the whole tree", ctx do
      # 10 doubling + 2 flat: 12M → 22M total (1.83x), median ratio 2.0.
      seed(@programming, 10, 1_000_000, 2_000_000, ctx)
      seed(@programming, 2, 1_000_000, 1_000_000, ctx)

      data = IndustryGrowth.load(:ee)
      class = data.nodes[@programming]

      assert class.companies == 12
      assert Decimal.equal?(class.base_total, Decimal.new(12_000_000))
      assert Decimal.equal?(class.latest_total, Decimal.new(22_000_000))
      assert Decimal.equal?(class.change, Decimal.new(10_000_000))
      assert_in_delta class.total_ratio, 22 / 12, 0.001
      assert_in_delta class.median_ratio, 2.0, 0.001
      refute class.thin?

      # Group, division and section carry the same figures — this class is all
      # there is under them.
      for node <- ~w(621 62 K) do
        assert data.nodes[node].companies == 12
        assert_in_delta data.nodes[node].total_ratio, 22 / 12, 0.001
      end

      assert data.market_total.companies == 12
      assert_in_delta data.market_total.total_ratio, 22 / 12, 0.001
    end

    test "a median is taken over companies, not over child industries", ctx do
      # One big grower and many small shrinkers under division 62: summed
      # revenue rises while the typical company falls.
      seed(@programming, 1, 1_000_000, 40_000_000, ctx)
      seed("6290", 11, 2_000_000, 1_000_000, ctx)

      division = IndustryGrowth.load(:ee).nodes["62"]

      assert division.companies == 12
      assert division.total_ratio > 1.0
      assert_in_delta division.median_ratio, 0.5, 0.001
    end

    test "share is a node's cut of the market's latest-year revenue", ctx do
      seed(@programming, 10, 1_000_000, 3_000_000, ctx)
      seed(@meat, 10, 1_000_000, 1_000_000, ctx)

      data = IndustryGrowth.load(:ee)

      assert_in_delta data.nodes[@programming].share, 0.75, 0.001
      assert_in_delta data.nodes[@meat].share, 0.25, 0.001
      assert_in_delta data.market_total.share, 1.0, 0.001
    end

    test "thin industries keep their row and their revenue but report no growth", ctx do
      seed(@programming, 9, 1_000_000, 30_000_000, ctx)

      data = IndustryGrowth.load(:ee)
      class = data.nodes[@programming]

      assert class.thin?
      assert class.companies == 9
      assert is_nil(class.total_ratio)
      assert is_nil(class.median_ratio)
      # Still counted where it matters: the market total sees the revenue.
      assert Decimal.equal?(class.latest_total, Decimal.new(270_000_000))
      assert data.market_total.companies == 9
    end

    test "ten companies is enough to rank", ctx do
      seed(@programming, 10, 1_000_000, 2_000_000, ctx)

      refute IndustryGrowth.load(:ee).nodes[@programming].thin?
    end

    test "counts only companies that filed revenue in both years", ctx do
      seed(@programming, 10, 1_000_000, 2_000_000, ctx)
      # Filed only the latest year, only the base year, or neither.
      seed(@programming, 1, nil, 9_000_000, ctx)
      seed(@programming, 1, 9_000_000, nil, ctx)
      company(@programming)

      assert IndustryGrowth.load(:ee).nodes[@programming].companies == 10
    end

    test "excludes companies under the revenue floor in the latest year", ctx do
      seed(@programming, 10, 1_000_000, 2_000_000, ctx)
      seed(@programming, 3, 100_000, IndustryGrowth.min_revenue_eur() - 1, ctx)

      assert IndustryGrowth.load(:ee).nodes[@programming].companies == 10
    end

    test "keeps a company that cleared the floor only in the latest year", ctx do
      seed(@programming, 10, 1_000_000, 2_000_000, ctx)
      seed(@programming, 1, 100_000, 1_000_000, ctx)

      class = IndustryGrowth.load(:ee).nodes[@programming]

      assert class.companies == 11
      assert_in_delta class.median_ratio, 2.0, 0.001
    end

    test "excludes companies with no revenue to grow from", ctx do
      seed(@programming, 10, 1_000_000, 2_000_000, ctx)
      seed(@programming, 2, 0, 9_000_000, ctx)

      assert IndustryGrowth.load(:ee).nodes[@programming].companies == 10
    end

    test "attributes 5-digit EMTAK codes to their 4-digit NACE class", ctx do
      seed("62101", 6, 1_000_000, 2_000_000, ctx)
      seed("62109", 4, 1_000_000, 2_000_000, ctx)

      assert IndustryGrowth.load(:ee).nodes[@programming].companies == 10
    end

    test "keeps markets apart", ctx do
      seed(@programming, 10, 1_000_000, 2_000_000, ctx)
      seed(@programming, 10, 1_000_000, 5_000_000, ctx, market: :fi)

      assert_in_delta IndustryGrowth.load(:ee).nodes[@programming].total_ratio, 2.0, 0.001
      assert_in_delta IndustryGrowth.load(:fi).nodes[@programming].total_ratio, 5.0, 0.001
    end

    test "an empty cohort reports no market rather than crashing", ctx do
      seed(@programming, 3, nil, 2_000_000, ctx)

      data = IndustryGrowth.load(:ee)

      assert data.market_total == nil
      assert data.nodes == %{}
    end

    test "years_available reports what the market has on file", ctx do
      seed(@programming, 1, 1_000_000, 2_000_000, ctx)

      assert IndustryGrowth.load(:ee).years_available == [
               {ctx.latest_year, 1},
               {ctx.base_year, 1}
             ]
    end
  end
end
