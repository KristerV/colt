# Regenerates `lib/colt/filters/industry_labels.ex` from two sources:
#   1. NACE Rev. 2 English JSON dump (Eurostat-derived)
#      https://raw.githubusercontent.com/KeyteqLabs/node-nace-codes/master/resources/nace.json
#   2. EMTAK 2008 selgitavad märkused (PRIA mirror — same NACE classes,
#      Estonian labels). Layout-extracted via `pdftotext -layout`.
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/KeyteqLabs/node-nace-codes/master/resources/nace.json -o /tmp/nace.json
#   curl -sL "https://www.pria.ee/sites/default/files/2021-06/EMTAK_2008%20%282%29.pdf" -o /tmp/emtak.pdf
#   pdftotext -layout /tmp/emtak.pdf /tmp/emtak_l.txt
#   mix run priv/scripts/gen_industry_labels.exs

# --- English (NACE) ---
en_list = "/tmp/nace.json" |> File.read!() |> Jason.decode!()

en_for = fn level ->
  en_list
  |> Enum.filter(&(&1["level"] == level))
  |> Enum.map(fn %{"code" => code, "name" => name} ->
    {String.replace(code, ".", ""), name}
  end)
  |> Map.new()
end

en_divisions = en_for.(2)
en_groups = en_for.(3)
en_classes = en_for.(4)

# --- Estonian (EMTAK 2008) ---
# Note: `pdftotext -layout` preserves columns; the plain output flattens them
# and the parser fails. Always use `-layout`.
et_lines = "/tmp/emtak_l.txt" |> File.stream!() |> Enum.to_list()

et_for = fn n ->
  re = Regex.compile!("^\\s*(\\d{#{n}})(?!\\d)\\s+(.+?)\\s*$", "u")

  et_lines
  |> Enum.flat_map(fn line ->
    case Regex.run(re, line) do
      [_, code, label] ->
        cond do
          String.contains?(label, "EMTAK 2008") -> []
          true -> [{code, String.trim(label)}]
        end

      _ ->
        []
    end
  end)
  |> Enum.uniq_by(&elem(&1, 0))
  |> Map.new()
end

et_divisions = et_for.(2)
et_groups = et_for.(3)
et_classes = et_for.(4)

# --- Merge into {code => {en, et}} ---
merge = fn en, et ->
  Map.keys(en)
  |> Enum.concat(Map.keys(et))
  |> Enum.uniq()
  |> Enum.sort()
  |> Enum.map(fn k -> {k, Map.get(en, k), Map.get(et, k)} end)
end

dump = fn rows ->
  rows
  |> Enum.map(fn {k, en, et} ->
    en_s = en |> to_string() |> String.replace("\"", "\\\"")
    et_s = if et, do: "\"#{String.replace(et, "\"", "\\\"")}\"", else: "nil"
    "    \"#{k}\" => {\"#{en_s}\", #{et_s}}"
  end)
  |> Enum.join(",\n")
end

classes = merge.(en_classes, et_classes)
groups = merge.(en_groups, et_groups)
divisions = merge.(en_divisions, et_divisions)

content = """
defmodule Colt.Filters.IndustryLabels do
  @moduledoc \"\"\"
  EMTAK / NACE Rev. 2 code → bilingual label.

  Each level (class / group / division) maps a code to `{en, et}`. The first
  4 digits of an EMTAK 5-digit code are NACE Rev. 2; the 5th digit is a
  national subclass that doesn't change the wording, so we label off the
  NACE class.

  Lookup order (`label/1`): 4-digit class → 3-digit group → 2-digit division.
  Returns the English label by default; `label/2` takes `:en` or `:et`.

  Search (`search/2`) matches the query as a code prefix or as a substring
  in either the English or Estonian label.

  Sources: NACE Rev. 2 EN from KeyteqLabs/node-nace-codes (615 classes /
  272 groups / 88 divisions); ET from EMTAK 2008 selgitavad märkused
  (PRIA mirror). Regenerate with `priv/scripts/gen_industry_labels.exs`.
  \"\"\"

  @classes %{
#{dump.(classes)}
  }

  @groups %{
#{dump.(groups)}
  }

  @divisions %{
#{dump.(divisions)}
  }

  def label(code), do: label(code, :en)

  def label(code, lang) when is_binary(code) and lang in [:en, :et] do
    key4 = String.slice(code, 0, 4)
    key3 = String.slice(code, 0, 3)
    key2 = String.slice(code, 0, 2)

    pair =
      Map.get(@classes, key4) ||
        Map.get(@groups, key3) ||
        Map.get(@divisions, key2)

    case {pair, lang} do
      {nil, _} -> nil
      {{en, _}, :en} -> en
      {{en, nil}, :et} -> en
      {{_, et}, :et} -> et
    end
  end

  def label(_, _), do: nil

  @doc \"\"\"
  Substring/prefix search over the 615 NACE classes. Returns up to `limit`
  `{code, en_label}` pairs. Matches code-prefix first, then substring hits in
  either the English or the Estonian label, ranked by EN-label length.
  \"\"\"
  def search(query, limit \\\\ 20) when is_binary(query) do
    q = query |> String.trim() |> String.downcase()

    if q == "" do
      []
    else
      @classes
      |> Enum.reduce([], fn {code, {en, et}}, acc ->
        en_d = String.downcase(en)
        et_d = if et, do: String.downcase(et), else: ""

        cond do
          String.starts_with?(code, q) -> [{0, String.length(en), {code, en}} | acc]
          String.contains?(en_d, q) -> [{1, String.length(en), {code, en}} | acc]
          et_d != "" and String.contains?(et_d, q) -> [{1, String.length(en), {code, en}} | acc]
          true -> acc
        end
      end)
      |> Enum.sort()
      |> Enum.take(limit)
      |> Enum.map(fn {_, _, entry} -> entry end)
    end
  end
end
"""

File.write!("lib/colt/filters/industry_labels.ex", content)
IO.puts("wrote #{byte_size(content)} bytes")
IO.puts("classes: #{length(classes)} (#{Enum.count(classes, fn {_,_,et} -> et end)} with ET)")
IO.puts("groups:  #{length(groups)} (#{Enum.count(groups, fn {_,_,et} -> et end)} with ET)")
IO.puts("divisions: #{length(divisions)} (#{Enum.count(divisions, fn {_,_,et} -> et end)} with ET)")
