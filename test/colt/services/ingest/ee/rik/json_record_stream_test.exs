defmodule Colt.Services.Ingest.Ee.Rik.JsonRecordStreamTest do
  use ExUnit.Case, async: true

  alias Colt.Services.Ingest.Ee.Rik.JsonRecordStream

  @fixture Path.join([:code.priv_dir(:colt), "fixtures", "rik_ee", "yldandmed.json"])

  test "streams every top-level record as a decoded map" do
    {:ok, stream} = JsonRecordStream.run(@fixture)
    records = Enum.to_list(stream)

    assert length(records) == 7
    codes = Enum.map(records, & &1["ariregistri_kood"])

    assert codes == [
             10_000_001,
             10_000_002,
             10_000_003,
             10_000_004,
             10_000_005,
             10_000_006,
             10_000_007
           ]
  end

  test "preserves nested structure (sidevahendid, teatatud_tegevusalad)" do
    {:ok, stream} = JsonRecordStream.run(@fixture)
    [alpha | _] = Enum.to_list(stream)

    assert alpha["nimi"] == "Alpha Growth OÜ"
    assert is_list(alpha["yldandmed"]["sidevahendid"])
    assert is_list(alpha["yldandmed"]["teatatud_tegevusalad"])

    www = Enum.find(alpha["yldandmed"]["sidevahendid"], &(&1["liik"] == "WWW"))
    assert www["sisu"] == "https://alpha.ee"
  end

  test "tolerates compact JSON with no whitespace" do
    path = Path.join(System.tmp_dir!(), "compact_#{:rand.uniform(1_000_000)}.json")
    File.write!(path, ~s/[{"a":1,"b":"x{}\\"y"},{"a":2}]/)

    try do
      {:ok, stream} = JsonRecordStream.run(path)
      assert Enum.to_list(stream) == [%{"a" => 1, "b" => "x{}\"y"}, %{"a" => 2}]
    after
      File.rm(path)
    end
  end

  test "tolerates an empty array" do
    path = Path.join(System.tmp_dir!(), "empty_#{:rand.uniform(1_000_000)}.json")
    File.write!(path, "[\n]\n")

    try do
      {:ok, stream} = JsonRecordStream.run(path)
      assert Enum.to_list(stream) == []
    after
      File.rm(path)
    end
  end

  test "returns {:error, _} for missing file" do
    assert {:error, {:not_found, _}} = JsonRecordStream.run("/nope/does-not-exist.json")
  end
end
