defmodule Colt.Services.Email.SplitQuoteHtml do
  @moduledoc """
  Split an HTML email body into the new message and the quoted history below it.

  The tree-level sibling of `Colt.Services.Email.SplitQuote`, which works on
  flattened text and stays in use for LLM input. Rendering the timeline as HTML
  means the split has to happen on the tree instead, and that's an improvement:
  clients mark the quote structurally — Gmail's `div.gmail_quote`, a
  `<blockquote>`, Outlook's `#divRplyFwdMsg` / `#appendonsend`, Thunderbird's
  `.moz-cite-prefix` — and only fall back to a text attribution line
  ("On … wrote:") when they don't.

  Must run *before* `Colt.Services.Email.SanitizeHtml`, which strips the very
  `class` and `id` attributes those structural markers live in.

  Returns `{:ok, %{body: html, quoted: html_or_nil}}`. A body that is entirely
  quote is left whole, since there'd be nothing left to show.
  """

  @quote_ids ~w(divRplyFwdMsg appendonsend)
  @quote_classes ~w(gmail_quote gmail_quote_container moz-cite-prefix
                    yahoo_quoted protonmail_quote)

  # Anchored variants of SplitQuote's markers. There they scan a whole flattened
  # body for the earliest hit; here each one is tested against a single node's
  # own text, so the marker has to *open* that node to count.
  @attribution [
    ~r/\A\s*-{2,}\s*Original Message\s*-{2,}/i,
    ~r/\A\s*From:\s\S/,
    ~r/\A\s*(?:On|Le|Am|El)\s.{0,200}\b(?:wrote|kirjutas|schrieb|a écrit|escribió)\s*:/su,
    ~r/\A\s*.{0,200}\b(?:kirjutas|wrote)\s*:\s*\z/su,
    ~r/\A\s*_{10,}\s*\z/
  ]

  def run(html, _opts \\ [])

  def run(html, _opts) when is_binary(html) do
    with {:ok, nodes} <- Floki.parse_fragment(html),
         {body, [_ | _] = quoted} <- split(nodes),
         false <- blank?(body) do
      {:ok, %{body: raw(body), quoted: raw(quoted)}}
    else
      # No marker, nothing above the marker, or unparseable — show it whole.
      _ -> {:ok, %{body: html, quoted: nil}}
    end
  rescue
    # A malformed body must never take a thread down.
    _ -> {:ok, %{body: html, quoted: nil}}
  end

  def run(_html, _opts), do: {:ok, %{body: "", quoted: nil}}

  # ── Tree walk ───────────────────────────────────────────────────────

  defp split(nodes) do
    case Enum.find_index(nodes, &quote_start?/1) do
      nil -> descend(nodes)
      i -> {Enum.take(nodes, i), Enum.drop(nodes, i)}
    end
  end

  # No marker among these siblings. Real mail wraps the whole message in a
  # container div, so the quote is usually a level down — recurse into the first
  # child that holds a marker and rebuild both halves around it, keeping that
  # wrapper on both sides so neither half loses its styling.
  defp descend(nodes) do
    case Enum.find_index(nodes, &contains_marker?/1) do
      nil ->
        {nodes, []}

      i ->
        {tag, attrs, children} = Enum.at(nodes, i)

        case split(children) do
          {_inner_body, []} ->
            {nodes, []}

          {inner_body, inner_quoted} ->
            {Enum.take(nodes, i) ++ [{tag, attrs, inner_body}],
             [{tag, attrs, inner_quoted} | Enum.drop(nodes, i + 1)]}
        end
    end
  end

  # ── Markers ─────────────────────────────────────────────────────────

  # Is this node itself the first thing belonging to the quote?
  defp quote_start?({"blockquote", _attrs, _children}), do: true
  defp quote_start?({"hr", attrs, _children}), do: id(attrs) == "stopSpelling"

  defp quote_start?({_tag, attrs, _children} = node) do
    id(attrs) in @quote_ids or
      Enum.any?(@quote_classes, &(&1 in classes(attrs))) or
      attribution?(Floki.text(node))
  end

  defp quote_start?(text) when is_binary(text), do: attribution?(text)
  defp quote_start?(_node), do: false

  # Is there a marker anywhere inside? Drives the descent, so it looks past the
  # wrapper that `quote_start?/1` deliberately refuses to match.
  defp contains_marker?({_tag, _attrs, children} = node) do
    quote_start?(node) or Enum.any?(children, &contains_marker?/1)
  end

  defp contains_marker?(text) when is_binary(text), do: attribution?(text)
  defp contains_marker?(_node), do: false

  defp attribution?(text), do: Enum.any?(@attribution, &Regex.match?(&1, text))

  # ── Helpers ─────────────────────────────────────────────────────────

  defp id(attrs), do: attr(attrs, "id")

  defp classes(attrs), do: attrs |> attr("class") |> String.split(~r/\s+/, trim: true)

  defp attr(attrs, name) do
    Enum.find_value(attrs, "", fn {k, v} -> if String.downcase(k) == name, do: v end)
  end

  # An image-only half still has something to show, so text alone can't decide.
  defp blank?(nodes) do
    nodes |> Floki.text() |> String.trim() == "" and Floki.find(nodes, "img") == []
  end

  defp raw(nodes), do: Floki.raw_html(nodes, encode: true)
end
