defmodule Colt.Services.Ingest.Lv.Ur.IndustryCodesTest do
  @moduledoc """
  Covers the NACE revision rules for Latvia (`docs/countries/industry-codes.md`,
  checklist item 5). The cases that matter are the two collision rows: Latvia
  knows each row's revision from its tax year, so a reused code is safe on a
  Rev-2.1 row and undecidable only on a Rev-2 one.
  """

  use Colt.DataCase, async: false

  require Ash.Query

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Lv.Ur.IndustryCodes

  @fixture Path.join([:code.priv_dir(:colt), "fixtures", "ur_lv", "vid_taxes_3y.csv"])

  setup do
    tmp = Path.join(System.tmp_dir!(), "ur_lv_fixtures_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    File.cp!(@fixture, Path.join(tmp, "vid_taxes_3y.csv"))

    prev = Application.get_env(:colt, :ur_lv_cache_dir)
    Application.put_env(:colt, :ur_lv_cache_dir, tmp)

    on_exit(fn ->
      Application.put_env(:colt, :ur_lv_cache_dir, prev)
      File.rm_rf!(tmp)
    end)

    for code <- Enum.map(1..9, &"4000000000#{&1}") do
      Ash.create!(Company, %{registry_code: code, market: :lv, name: "Fixture #{code}"},
        action: :upsert_basic,
        upsert?: true,
        upsert_identity: :registry_code_market
      )
    end

    :ok
  end

  defp industry_code(registry_code) do
    Company
    |> Ash.Query.filter(registry_code == ^registry_code and market == :lv)
    |> Ash.read_one!()
    |> Map.fetch!(:industry_code)
  end

  test "a Rev-2 class that Rev 2.1 removed is translated forward" do
    {:ok, _} = IndustryCodes.run()
    assert industry_code("40000000001") == "6210"
  end

  test "a Rev-2.1 code passes through untouched" do
    {:ok, _} = IndustryCodes.run()
    assert industry_code("40000000002") == "6210"
  end

  test "a reused code on a Rev-2 row is dropped rather than mislabelled" do
    {:ok, _} = IndustryCodes.run()
    assert industry_code("40000000003") == nil
  end

  # The payoff for knowing the revision: LT has to null every collision, LV
  # only has to null the ones filed under Rev. 2.
  test "the same reused code on a Rev-2.1 row is kept" do
    {:ok, _} = IndustryCodes.run()
    assert industry_code("40000000004") == "4781"
  end

  # The 429 rows proving the year alone is not sufficient.
  test "a Rev-2-only class is translated even when filed under a Rev-2.1 year" do
    {:ok, _} = IndustryCodes.run()
    assert industry_code("40000000005") == "6210"
  end

  test "the newest tax year wins over an older filing" do
    {:ok, _} = IndustryCodes.run()
    assert industry_code("40000000006") == "6820"
  end

  test "a legal name containing commas and quotes does not shift the columns" do
    {:ok, _} = IndustryCodes.run()
    assert industry_code("40000000007") == "9531"
  end

  test "a company declaring no activity is left without a code" do
    {:ok, _} = IndustryCodes.run()
    assert industry_code("40000000008") == nil
  end

  # Division 45 no longer exists; car repair is 95.31 in Rev. 2.1. This is the
  # code the playbook's end-to-end sanity check picks in the filter UI.
  test "car repair migrates out of the deleted division 45" do
    {:ok, _} = IndustryCodes.run()
    assert industry_code("40000000009") == "9531"
  end

  test "reports assigned, dropped and unmatched counts" do
    {:ok, stats} = IndustryCodes.run()

    # 8 of the 9 fixture companies produce a row (40000000008 declared "?"),
    # and only the Rev-2 collision is undecidable.
    assert stats.assigned == 7
    assert stats.dropped == 1
    # The foreign taxpayer has no company row in our table.
    assert stats.unmatched == 1
  end

  test "a stale code is cleared on re-run rather than left behind" do
    {:ok, _} = IndustryCodes.run()
    assert industry_code("40000000003") == nil

    Ash.create!(
      Company,
      %{
        registry_code: "40000000003",
        market: :lv,
        name: "Fixture 40000000003",
        industry_code: "9999"
      },
      action: :upsert_details,
      upsert?: true,
      upsert_identity: :registry_code_market
    )

    assert industry_code("40000000003") == "9999"

    {:ok, _} = IndustryCodes.run()
    assert industry_code("40000000003") == nil
  end
end
