# Regenerates `lib/colt/filters/nace_migration.ex` from the two correspondence
# tables checked in under `priv/nace/`.
#
#   mix run priv/scripts/gen_nace_migration.exs
#
# Why the sources are vendored rather than curl'd (unlike gen_industry_labels.exs):
# the RIK table is only reachable from its search UI and needs a `__Host-ariregweb`
# session cookie, so a documented one-liner would rot. Both files are ~50KB total.
#
#   priv/nace/emtak_2008_to_2025.csv
#     RIK "üleminekutabel", EMTAK 2008 -> EMTAK 2025, all levels (2/3/4/5-digit).
#     https://ariregister.rik.ee/est/emtak_search__corresp_tables
#       ?file_type=csv&correspondence=2008_EMTAK_2025 (needs the session cookie)
#     NB: the /est/api/corresp_table_autocomplete JSON endpoint looks like the same
#     data but is DISTINCT ON (source) server-side — it silently keeps only the first
#     target per source and collapses every 1:many. Do not use it.
#
#   priv/nace/nace_rev2_to_rev21.csv
#     Eurostat "CorresTab_NACE Rev.2-NACE Rev.2.1" v1.05, 4-digit classes only.
#     https://showvoc.op.europa.eu/ -> NACE Rev. 2.1 -> correspondence tables
#
# Both tables list *any* overlap however marginal, so a source code can name targets
# that carry a sliver of its activity (EMTAK 96099 "muu teenindus" lists 23159, glass
# manufacturing). Resolution rules below, in order:
#
#   1. all targets share one NACE-4  -> that code. Deterministic.
#   2. the source's own NACE-4 is among the targets -> keep the source code. The class
#      survived into Rev 2.1 and merely shed some activities; staying put is correct
#      for the bulk and never wrong-by-meaning.
#   3. an explicit pick in @emtak_picks / @nace_picks -> that code. Judgement calls,
#      reviewed by volume.
#   4. exactly one target shares the source's division -> that code.
#   5. otherwise -> nil. The row loses its industry code rather than assert a guess.
#
# Rules 1+2 cover 74.7% of Estonia's 117,005 Rev-2 rows on their own.

alias NimbleCSV.RFC4180, as: CSV

# --- judgement calls, ordered by how many EE rows each carries -----------------
# Reviewed against RIK's Estonian labels. `nil` = deliberately dropped: the class
# dissolved across too many targets to guess (47911/47991/82991 are the "sold via
# mail/internet" and "other business support" classes NACE 2.1 broke up by product).
emtak_picks = %{
  # 3803 rows. Target label is identical to the source's.
  "41201" => "41001",
  # 3151. Hairdressing is the bulk; the 9622x beauty sub-classes are the tail.
  "96021" => "96211",
  # 2385. Taxi -> chauffeured passenger transport.
  "49321" => "49331",
  # 1927. Identical label.
  "64201" => "64211",
  # 1673. Funds proper, not the 64321 trust/escrow tail.
  "64301" => "64311",
  # 1358. Restaurants/cafes over fast-food and mobile.
  "56101" => "56111",
  # 1250 / 1189. Alternate target is 2315x (glass manufacturing) — table noise.
  "96099" => "96999",
  "9609" => "9699",
  # 1238. The n.e.c. catch-all, not patent brokering (74911) or security (80091).
  "74901" => "74991",
  # 1178. MEDIUM confidence: artistic creation -> "muu kunstiloome" catch-all,
  # over literary (90111) / visual (90121).
  "90031" => "90131",
  # 938. MEDIUM confidence: concert staging -> musicians' stage activity, over
  # composing (90112).
  "90012" => "90202",
  # 757. "Retail in other non-specialised stores" -> its direct successor; the
  # alternative (47911) is the online-brokerage carve-out.
  "47191" => "47121",
  # 742. MEDIUM confidence: designers -> the "other design" catch-all, since the
  # source doesn't say which of industrial/graphic/interior a firm does.
  "74101" => "74141",
  # 700 / 473 / 219. Target label is identical (or near-identical) to the source's.
  "43391" => "43351",
  "86909" => "86992",
  "45321" => "47821",
  # 582. A car seller is retail, not a wholesale agent. Matches the "4511" NACE pick.
  "45111" => "47811",
  # 438. Hosting infrastructure (NACE 63.10), not TV/content distribution.
  "63111" => "63101",
  # 294. MEDIUM confidence: market-stall textiles/clothing/shoes -> clothing retail,
  # the largest of the three.
  "47821" => "47711",
  # 245. Non-knitted outerwear.
  "14131" => "14211",
  # 1035 / 2742 / 2440. 42, 44 and 24 targets respectively — unguessable.
  "47991" => nil,
  "47911" => nil,
  "82991" => nil
}

# --- same, for the NACE-4 table (markets with no classifier version) -----------
nace_picks = %{
  # Division 45 is dissolved in Rev 2.1; a car *seller* is most likely retail.
  "4511" => "4781",
  "4519" => "4781",
  "4531" => "4672",
  "4540" => "4783",
  # Restructured by product across 17 and 29 targets.
  "4789" => nil,
  "4799" => nil
}

read = fn path ->
  path |> File.read!() |> String.replace_prefix("﻿", "")
end

# --- EMTAK 2008 -> EMTAK 2025 -------------------------------------------------
emtak_rows =
  Path.join(:code.priv_dir(:colt), "nace/emtak_2008_to_2025.csv")
  |> read.()
  |> CSV.parse_string(skip_headers: true)
  |> Enum.flat_map(fn
    [a, b | _] when a != "" and b != "" -> [{String.trim(a), String.trim(b)}]
    _ -> []
  end)
  |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

# --- NACE Rev.2 -> Rev.2.1 ----------------------------------------------------
nace_rows =
  Path.join(:code.priv_dir(:colt), "nace/nace_rev2_to_rev21.csv")
  |> read.()
  |> CSV.parse_string(skip_headers: true)
  |> Enum.flat_map(fn
    [a, b | _] when a != "" and b != "" -> [{a, b}]
    _ -> []
  end)
  |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

nace4 = fn code -> String.slice(code, 0, 4) end
div2 = fn code -> String.slice(code, 0, 2) end

resolve = fn source, targets, picks ->
  target_n4 = targets |> Enum.map(nace4) |> Enum.uniq()
  same_div = Enum.filter(targets, &(div2.(&1) == div2.(source)))

  cond do
    Map.has_key?(picks, source) -> Map.fetch!(picks, source)
    length(target_n4) == 1 -> hd(targets)
    nace4.(source) in target_n4 -> source
    length(same_div) == 1 -> hd(same_div)
    true -> nil
  end
end

emtak_map =
  Map.new(emtak_rows, fn {source, targets} ->
    {source, resolve.(source, targets, emtak_picks)}
  end)

# Only Rev-2 classes that no longer exist in Rev 2.1 need rewriting; everything else
# is either already valid or a collision (handled separately).
rev2 = MapSet.new(Map.keys(nace_rows))
rev21 = nace_rows |> Map.values() |> List.flatten() |> MapSet.new()
rev2_only = MapSet.difference(rev2, rev21)

# Codes valid in BOTH revisions but NOT mapping to themselves: Rev 2.1 reused the
# string for an unrelated activity (4781 is a market food stall in Rev 2 and a car
# dealership in Rev 2.1). Undecidable without a classifier version.
collisions =
  rev2
  |> MapSet.intersection(rev21)
  |> Enum.reject(&(&1 in Map.fetch!(nace_rows, &1)))
  |> Enum.sort()

nace_map =
  rev2_only
  |> Enum.map(fn source ->
    {source, resolve.(source, Map.fetch!(nace_rows, source), nace_picks)}
  end)
  |> Map.new()

fmt = fn map ->
  map
  |> Enum.sort()
  |> Enum.map_join(",\n", fn {k, v} ->
    ~s(    #{inspect(k)} => #{inspect(v)})
  end)
end

resolved = fn map -> Enum.count(map, fn {_, v} -> not is_nil(v) end) end

body = """
# This file is generated by priv/scripts/gen_nace_migration.exs — do not edit.
# Regenerate with: mix run priv/scripts/gen_nace_migration.exs
defmodule Colt.Filters.NaceMigration do
  @moduledoc \"\"\"
  Forward-translates legacy industry codes to NACE Rev. 2.1.

  Estonia switched to EMTAK 2025 (= NACE Rev. 2.1) on 2025-01-01, Norway to SN2025,
  Finland and Lithuania likewise. None of the registries re-classified their back
  catalogue, so every feed serves a mix: a company keeps its old code until it next
  re-declares. `companies.industry_code` therefore has to hold one vocabulary, and
  Rev. 2.1 is the one the data is converging on — Norway is already 100% Rev 2.1,
  Finland 99.96%, Estonia 71%.

  Translating on the way in (rather than backfilling once) means re-running an
  ingestion job self-heals, and the mapping decays to a no-op as registries migrate.

  Two tables, because two kinds of source:

    * `emtak_2008_to_2025/1` — Estonia. RIK tags every activity with
      `emtak_versioon` (2 = EMTAK 2008, 3 = EMTAK 2025), so we know a row's revision
      exactly and translate only the old ones, at 5-digit EMTAK granularity.

    * `nace_rev2_to_rev21/1` — Lithuania (Sodra `evrk`) and any future feed with no
      version field. Coarser and lossier: it can only act on codes that Rev 2.1
      deleted outright, and must drop the #{length(collisions)} codes Rev 2.1 reused
      for an unrelated activity (see `collision?/1`).

  `LEFT(industry_code, 4)` stays the filter key: `emtak_kood` is always its
  `nace_kood` plus a national subclass digit (verified across all 414,821 activity
  records in the RIK dump), so translating at EMTAK level keeps that detail intact.
  \"\"\"

  # EMTAK 2008 -> EMTAK 2025. #{resolved.(emtak_map)} of #{map_size(emtak_map)} codes resolve; the rest are nil
  # (dissolved across too many targets to pick one).
  @emtak %{
#{fmt.(emtak_map)}
  }

  # NACE Rev. 2 -> Rev. 2.1, for the classes Rev 2.1 removed. Codes valid in both
  # revisions are absent: they need no rewrite.
  @nace %{
#{fmt.(nace_map)}
  }

  # Valid in both revisions, with different meanings in each.
  @collisions ~w(#{Enum.join(collisions, " ")})

  @doc \"\"\"
  Estonian EMTAK 2008 code -> its EMTAK 2025 equivalent.

  Returns `nil` when the old class dissolved across too many Rev 2.1 classes to pick
  one — the company loses its industry code rather than get a fabricated one, and
  regains it when it re-declares.
  \"\"\"
  def emtak_2008_to_2025(code) when is_binary(code), do: Map.get(@emtak, code)
  def emtak_2008_to_2025(_), do: nil

  @doc \"\"\"
  Best-effort forward translation for a feed with no classifier version.

  Takes a full code (EVRK/NACE, any length) and returns it unchanged when its class
  is still valid in Rev 2.1, a rewritten 4-digit code when Rev 2.1 removed the class,
  or `nil` when the code is ambiguous between revisions.
  \"\"\"
  def nace_rev2_to_rev21(code) when is_binary(code) and byte_size(code) >= 4 do
    head = String.slice(code, 0, 4)

    cond do
      head in @collisions -> nil
      Map.has_key?(@nace, head) -> Map.fetch!(@nace, head)
      true -> code
    end
  end

  def nace_rev2_to_rev21(code), do: code

  @doc \"\"\"
  Whether a 4-digit class means different things in Rev. 2 and Rev. 2.1.

  Only meaningful for feeds that don't tell us the revision; with a version field
  (Estonia) the code is never ambiguous.
  \"\"\"
  def collision?(code) when is_binary(code), do: String.slice(code, 0, 4) in @collisions
  def collision?(_), do: false
end
"""

path = "lib/colt/filters/nace_migration.ex"
File.write!(path, (body |> Code.format_string!() |> IO.iodata_to_binary()) <> "\n")

IO.puts("""
wrote #{path}
  EMTAK 2008 -> 2025 : #{resolved.(emtak_map)}/#{map_size(emtak_map)} resolved, #{map_size(emtak_map) - resolved.(emtak_map)} dropped
  NACE Rev2 -> Rev2.1: #{resolved.(nace_map)}/#{map_size(nace_map)} resolved, #{map_size(nace_map) - resolved.(nace_map)} dropped
  collisions         : #{length(collisions)}
""")
