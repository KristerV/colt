defmodule Colt.Services.Export.Csv do
  @moduledoc """
  Build the Instantly-format CSV for a finished campaign.

  One row per validated, title-matching Person on an enriched, opted-in
  CampaignCompany. Columns:

      email, first_name, last_name, company_name, website, title, snippet
  """

  alias Colt.Resources.{Campaign, CampaignCompany}

  @columns ~w(email first_name last_name company_name website title snippet)

  def run(%Campaign{} = campaign) do
    with {:ok, ccs} <- load_ccs(campaign),
         rows <- build_rows(ccs),
         csv <- encode(rows) do
      {:ok,
       %{
         csv: csv,
         rows: rows,
         filename: filename(campaign),
         row_count: length(rows)
       }}
    end
  end

  defp load_ccs(campaign) do
    CampaignCompany.list_for_export(campaign.id,
      actor: nil,
      authorize?: false,
      load: [:picked_person, :company]
    )
  end

  defp build_rows(ccs) do
    ccs
    |> Enum.filter(&match?(%{picked_person: %{}}, &1))
    |> Enum.uniq_by(&dedup_key(&1.picked_person))
    |> Enum.map(&row_for(&1.picked_person, &1.company))
  end

  # Persons table can carry duplicate rows when ExtractContacts ran
  # more than once for the same company. Collapse on email when present,
  # falling back to name so anonymous variants still merge.
  defp dedup_key(%{email: email}) when is_binary(email) and email != "",
    do: {:email, String.downcase(email)}

  defp dedup_key(%{name: name}) when is_binary(name),
    do: {:name, String.downcase(name)}

  defp dedup_key(p), do: {:id, p.id}

  defp row_for(person, company) do
    {first, last} = split_name(person.name)

    %{
      "email" => person.email || "",
      "first_name" => first,
      "last_name" => last,
      "company_name" => company.name || "",
      "website" => company.website_url || "",
      "title" => person.title || "",
      "snippet" => snippet(company.ai_summary)
    }
  end

  defp split_name(nil), do: {"", ""}

  defp split_name(name) do
    case String.split(name, ~r/\s+/, trim: true) do
      [] -> {"", ""}
      [single] -> {single, ""}
      [first | rest] -> {first, Enum.join(rest, " ")}
    end
  end

  defp snippet(nil), do: ""

  defp snippet(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 240)
  end

  defp encode(rows) do
    header = Enum.map_join(@columns, ",", &escape/1)

    body =
      Enum.map_join(rows, "\r\n", fn row ->
        Enum.map_join(@columns, ",", &escape(Map.get(row, &1, "")))
      end)

    case body do
      "" -> header <> "\r\n"
      _ -> header <> "\r\n" <> body <> "\r\n"
    end
  end

  defp escape(value) when not is_binary(value), do: escape(to_string(value))

  defp escape(value) do
    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end

  defp filename(%Campaign{name: name}) do
    "liid-#{slugify(name)}.csv"
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "campaign"
      slug -> slug
    end
  end
end
