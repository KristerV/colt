defmodule Colt.Services.Email.HtmlToText do
  @moduledoc """
  Email HTML → readable plain text, for display and for LLM input.

  Regex tag-stripping is not enough for real-world mail: it deletes the
  `<style>` tags but keeps their contents (Outlook ships a VML shim block that
  then renders as raw CSS), leaves `&nbsp;` undecoded, and only breaks lines on
  `<br>` — so Outlook's one-`<p>`-per-line markup collapses into a wall of text.

  Strategy:
    1. Parse with Floki.
    2. Drop non-content elements (style, script, head, …) subtree and all.
    3. Walk the tree, turning `<br>` and block-level elements into newlines.
    4. Take the text — Floki decodes entities on the way out.

  Returns `{:ok, text}`. Plain-text input (our own AI drafts) passes through
  normalization only.
  """

  # Removed with their contents, not just their tags.
  @drop ~w(style script head title meta link noscript svg)

  # Their boundaries become newlines.
  @block ~w(p div tr li h1 h2 h3 h4 h5 h6 blockquote table hr pre ul ol dl dt dd
            section article header footer address figure fieldset form)

  def run(html, _opts \\ [])

  def run(html, _opts) when is_binary(html) do
    text =
      if String.contains?(html, "<") do
        case Floki.parse_document(html) do
          {:ok, doc} -> render(doc)
          _ -> html
        end
      else
        html
      end

    {:ok, normalize(text)}
  rescue
    # Never let a malformed body take down a render or a classification.
    _ -> {:ok, normalize(html)}
  end

  def run(_html, _opts), do: {:ok, ""}

  # ── Tree walk ───────────────────────────────────────────────────────

  defp render(nodes) when is_list(nodes), do: Enum.map_join(nodes, "", &render/1)
  defp render(text) when is_binary(text), do: text
  defp render({tag, _attrs, _children}) when tag in @drop, do: ""
  defp render({"br", _attrs, _children}), do: "\n"
  defp render({tag, _attrs, children}) when tag in @block, do: "\n" <> render(children) <> "\n"
  defp render({_tag, _attrs, children}), do: render(children)
  defp render(_other), do: ""

  # ── Whitespace ──────────────────────────────────────────────────────

  defp normalize(text) when is_binary(text) do
    text
    |> String.replace(" ", " ")
    |> String.replace(~r/\r\n?/, "\n")
    |> String.replace(~r/[ \t]+/, " ")
    |> String.replace(~r/[ \t]+\n/, "\n")
    |> String.replace(~r/\n[ \t]+/, "\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  defp normalize(_), do: ""
end
