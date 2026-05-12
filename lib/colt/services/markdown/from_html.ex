defmodule Colt.Services.Markdown.FromHtml do
  @moduledoc """
  HTML → markdown conversion for the enrichment pipeline.

  Strategy:
    1. Parse with Floki.
    2. Strip nav, header, footer, script, style, noscript, iframe, svg.
    3. Serialize the cleaned DOM and hand to `Html2Markdown`.

  Returns `{:ok, markdown_string}` (possibly empty for unparseable input).
  """

  @strip_selectors ~w(nav header footer script style noscript iframe svg)

  def run(html, _opts \\ []) when is_binary(html) do
    cleaned =
      case Floki.parse_document(html) do
        {:ok, doc} ->
          Enum.reduce(@strip_selectors, doc, &Floki.filter_out(&2, &1))
          |> Floki.raw_html()

        _ ->
          html
      end

    md = Html2Markdown.convert(cleaned) |> scrub_utf8() |> normalize()
    {:ok, md}
  rescue
    e -> {:error, "markdown convert: #{Exception.message(e)}"}
  end

  defp normalize(md) do
    md
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  # Drop bytes that aren't valid UTF-8 so Postgres won't reject the insert.
  # Pages served as Latin-1 (mislabeled or no charset) leak stray bytes through
  # Html2Markdown.
  defp scrub_utf8(bin) when is_binary(bin), do: do_scrub(bin, <<>>)
  defp scrub_utf8(_), do: ""

  defp do_scrub(<<>>, acc), do: acc
  defp do_scrub(<<c::utf8, rest::binary>>, acc), do: do_scrub(rest, <<acc::binary, c::utf8>>)
  defp do_scrub(<<_, rest::binary>>, acc), do: do_scrub(rest, acc)
end
