defmodule Colt.Services.Enrichment.ExtractContentLinks do
  @moduledoc """
  Pull every same-host `<a href>` from a page (not just nav/header/footer).
  Used during recursive contact-page crawling: a `/kontakt` hub page may list
  per-office sub-paths (`/kontakt/tallinn`, …) that aren't reachable from the
  landing page's nav.
  """

  def run(html, base_url) when is_binary(html) and is_binary(base_url) do
    base = URI.parse(base_url)

    case Floki.parse_document(html) do
      {:ok, doc} ->
        links =
          doc
          |> Floki.find("a[href]")
          |> Enum.map(&link_pair(&1, base))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq_by(& &1.path)

        {:ok, links}

      _ ->
        {:ok, []}
    end
  end

  defp link_pair(anchor, base) do
    href = Floki.attribute(anchor, "href") |> List.first()
    title = anchor |> Floki.text() |> String.trim() |> trim_long()

    case normalise(href, base) do
      nil -> nil
      "/" -> nil
      path -> %{path: path, title: title}
    end
  end

  defp normalise(nil, _), do: nil
  defp normalise("#" <> _, _), do: nil
  defp normalise("mailto:" <> _, _), do: nil
  defp normalise("tel:" <> _, _), do: nil
  defp normalise("javascript:" <> _, _), do: nil

  defp normalise(href, base) do
    uri = URI.parse(href)

    cond do
      uri.host && same_host?(uri.host, base.host) -> path_of(uri)
      is_nil(uri.host) && is_binary(uri.path) -> path_of(uri)
      true -> nil
    end
  end

  defp same_host?(a, b) when is_binary(a) and is_binary(b),
    do: strip_www(a) == strip_www(b)

  defp same_host?(_, _), do: false

  defp strip_www(host), do: String.replace_prefix(host, "www.", "")

  defp path_of(%URI{path: nil}), do: "/"
  defp path_of(%URI{path: ""}), do: "/"
  defp path_of(%URI{path: p}), do: String.trim_trailing(p, "/") |> ensure_leading_slash()

  defp ensure_leading_slash(""), do: "/"
  defp ensure_leading_slash("/" <> _ = p), do: p
  defp ensure_leading_slash(p), do: "/" <> p

  defp trim_long(""), do: nil
  defp trim_long(text) when byte_size(text) > 80, do: String.slice(text, 0, 80)
  defp trim_long(text), do: text
end
