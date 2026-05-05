defmodule Colt.Services.Scrape.DetectSpa do
  @moduledoc """
  Heuristics from spec §6.3: decide whether a static fetch result needs the
  Wallaby fallback.

  Triggers:
    * body < 5 KB
    * `<body>` text content < 200 chars
    * SPA shell: `#root | #app | #__next | [data-reactroot] | [ng-app]`
    * `<noscript>` mentions "JavaScript" / "enable"
    * anchor count < 5

  Returns `{:ok, :static}` (good as-is) or `{:ok, :needs_wallaby}`.
  """

  @spa_selectors ["#root", "#app", "#__next", "[data-reactroot]", "[ng-app]"]

  def run(%{html: html}) when is_binary(html) do
    cond do
      byte_size(html) < 5_000 -> {:ok, :needs_wallaby}
      true -> inspect_dom(html)
    end
  end

  defp inspect_dom(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        cond do
          short_body?(doc) -> {:ok, :needs_wallaby}
          spa_shell?(doc) -> {:ok, :needs_wallaby}
          noscript_js_marker?(doc) -> {:ok, :needs_wallaby}
          anchor_count(doc) < 5 -> {:ok, :needs_wallaby}
          true -> {:ok, :static}
        end

      _ ->
        {:ok, :needs_wallaby}
    end
  end

  defp short_body?(doc) do
    text = doc |> Floki.find("body") |> Floki.text() |> String.trim()
    String.length(text) < 200
  end

  defp spa_shell?(doc) do
    Enum.any?(@spa_selectors, fn sel -> Floki.find(doc, sel) != [] end)
  end

  defp noscript_js_marker?(doc) do
    text = doc |> Floki.find("noscript") |> Floki.text() |> String.downcase()
    String.contains?(text, "javascript") or String.contains?(text, "enable")
  end

  defp anchor_count(doc), do: doc |> Floki.find("a") |> length()
end
