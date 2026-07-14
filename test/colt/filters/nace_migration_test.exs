defmodule Colt.Filters.NaceMigrationTest do
  @moduledoc """
  Guards the forward-translation to NACE Rev. 2.1.

  The invariant that matters: `LEFT(industry_code, 4)` must land on a class that
  `IndustryLabels` can actually offer, for every market, in either revision. Before
  this existed, Norway's 1.1M companies were ~36% unreachable by industry filter
  because the labels were Rev. 2 and the data had moved to Rev. 2.1.
  """

  use ExUnit.Case, async: true

  alias Colt.Filters.IndustryLabels
  alias Colt.Filters.NaceMigration

  describe "emtak_2008_to_2025/1" do
    test "translates a class NACE Rev 2.1 renumbered" do
      # Motor vehicle repair left section G for division 95 entirely.
      assert NaceMigration.emtak_2008_to_2025("45201") == "95311"
      assert NaceMigration.emtak_2008_to_2025("62011") == "62101"
    end

    test "keeps a class that survived the revision unchanged" do
      assert NaceMigration.emtak_2008_to_2025("73111") == "73111"
    end

    test "drops a class that dissolved across too many successors" do
      # 47911 fans out to 44 Rev 2.1 classes, 82991 to 24 — the old code carries no
      # information about which. Better unlabelled than fabricated.
      assert is_nil(NaceMigration.emtak_2008_to_2025("47911"))
      assert is_nil(NaceMigration.emtak_2008_to_2025("82991"))
    end

    test "returns nil for codes that are not EMTAK 2008" do
      assert is_nil(NaceMigration.emtak_2008_to_2025("99999"))
      assert is_nil(NaceMigration.emtak_2008_to_2025(""))
      assert is_nil(NaceMigration.emtak_2008_to_2025(nil))
    end

    test "every translated code resolves to a labelled Rev 2.1 class" do
      # The whole point: a translated code must be selectable in the UI. Codes below
      # 4 digits are declared at group/division level and label off those instead.
      for source <- ~w(45201 62011 73111 96021 56101 41201 64201),
          target = NaceMigration.emtak_2008_to_2025(source),
          not is_nil(target),
          String.length(target) >= 4 do
        class = String.slice(target, 0, 4)

        assert IndustryLabels.label(class),
               "#{source} -> #{target}, but #{class} has no Rev 2.1 label"
      end
    end
  end

  describe "nace_rev2_to_rev21/1" do
    test "rewrites a class Rev 2.1 removed" do
      assert NaceMigration.nace_rev2_to_rev21("452000") == "9531"
      # 41.10 moved out of Construction into Real estate.
      assert NaceMigration.nace_rev2_to_rev21("411000") == "6812"
    end

    test "leaves a class that is valid in both revisions alone" do
      assert NaceMigration.nace_rev2_to_rev21("702000") == "702000"
    end

    test "drops a code Rev 2.1 reused for an unrelated activity" do
      # 4781 is a market food stall in Rev 2 and a car dealership in Rev 2.1. Sodra
      # exposes no classifier version, so the code is genuinely undecidable.
      assert is_nil(NaceMigration.nace_rev2_to_rev21("478100"))
      assert NaceMigration.collision?("478100")
      assert NaceMigration.collision?("4781")
    end

    test "a code with no collision is not flagged as one" do
      refute NaceMigration.collision?("6210")
      refute NaceMigration.collision?("9531")
      refute NaceMigration.collision?(nil)
    end

    test "passes through codes too short to carry a class" do
      assert NaceMigration.nace_rev2_to_rev21("62") == "62"
      assert is_nil(NaceMigration.nace_rev2_to_rev21(nil))
    end
  end

  describe "the Rev 2.1 vocabulary" do
    test "division 45 no longer exists" do
      for code <- ~w(4511 4519 4520 4531 4532 4540) do
        refute IndustryLabels.label(code),
               "#{code} should not be offerable — Rev 2.1 dissolved division 45"
      end
    end

    test "section V exists (Rev 2.1 has 22 sections, Rev 2 had 21)" do
      letters = IndustryLabels.sections() |> Enum.map(&elem(&1, 0))
      assert "V" in letters
      assert length(letters) == 22
      refute IndustryLabels.expand_codes(["V"]) == []
    end

    test "picking motor vehicle repair expands to the Rev 2.1 class" do
      assert IndustryLabels.expand_codes(["9531"]) == ["9531"]
      assert "9531" in IndustryLabels.expand_codes(["953"])
      assert "9531" in IndustryLabels.expand_codes([IndustryLabels.section_of("9531")])
    end
  end
end
