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

    md = Html2Markdown.convert(cleaned) |> normalize()
    {:ok, md}
  rescue
    e -> {:error, "markdown convert: #{Exception.message(e)}"}
  end

  defp normalize(md) do
    md
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end
end
