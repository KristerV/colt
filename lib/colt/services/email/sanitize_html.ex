defmodule Colt.Services.Email.SanitizeHtml do
  @moduledoc """
  Reduce an email body to HTML that is safe to drop into the page with `raw/1`.

  Inbound bodies are attacker-controlled — a prospect can reply with anything,
  and a reply is rendered to an authenticated user inside their own session — so
  the timeline shows an allowlist rather than the original markup: known-good
  tags, a short list of attributes, `href`/`src` limited to safe schemes, and
  `style` filtered down to properties that can only change how a box looks.

  Two deliberate omissions from the allowlist:

    * `class` and `id`, so foreign markup can't reach our own selectors. This is
      why `Colt.Services.Email.SplitQuoteHtml` has to run *first* — it reads the
      quote markers that live in exactly those attributes.
    * anything positioning or scripting, so a body can't escape its card.

  Unknown-but-harmless tags are unwrapped rather than dropped, keeping their text
  in place. Returns `{:ok, html}`; `nil` in, `nil` out, so an absent quoted half
  stays absent.
  """

  # Dropped with their contents — their text is not body text.
  @drop ~w(script style head title meta link noscript iframe frame frameset object
           embed applet form input button select option textarea svg math base)

  @tags ~w(a b strong i em u s strike del ins mark small sub sup br hr p div span
           pre code kbd samp var blockquote q cite abbr time address
           ul ol li dl dt dd h1 h2 h3 h4 h5 h6 center font big tt
           table caption colgroup col thead tbody tfoot tr td th
           img figure figcaption picture source)

  @attrs ~w(href src srcset alt title width height colspan rowspan span align
            valign border cellpadding cellspacing bgcolor color face dir lang)

  @url_attrs ~w(href src srcset)

  @schemes ~w(http https mailto tel cid)

  # Presentational only. Nothing that positions, layers, floats out of the card,
  # loads a resource, or reaches outside its own box.
  @style_props ~w(color background-color background-image background font-weight
                  font-style font-size font-family font-variant text-align
                  text-decoration text-transform text-indent line-height
                  letter-spacing word-spacing white-space direction
                  padding padding-top padding-right padding-bottom padding-left
                  margin margin-top margin-right margin-bottom margin-left
                  border border-top border-right border-bottom border-left
                  border-color border-width border-style border-radius
                  border-collapse border-spacing
                  width min-width max-width height min-height max-height
                  vertical-align list-style list-style-type opacity)

  def run(html, _opts \\ [])

  def run(nil, _opts), do: {:ok, nil}

  def run(html, _opts) when is_binary(html) do
    case Floki.parse_fragment(html) do
      {:ok, nodes} -> {:ok, nodes |> Enum.flat_map(&clean/1) |> Floki.raw_html(encode: true)}
      _ -> {:ok, escape(html)}
    end
  rescue
    # Anything unexpected degrades to visible-but-inert text rather than to a
    # crashed thread or, worse, unfiltered markup.
    _ -> {:ok, escape(html)}
  end

  def run(_html, _opts), do: {:ok, ""}

  # ── Tree walk ───────────────────────────────────────────────────────

  defp clean({tag, _attrs, _children}) when tag in @drop, do: []

  defp clean({tag, attrs, children}) do
    cleaned = Enum.flat_map(children, &clean/1)

    if tag in @tags,
      do: [{tag, safe_attrs(attrs), cleaned}],
      else: cleaned
  end

  defp clean(text) when is_binary(text), do: [text]
  defp clean(_node), do: []

  # ── Attributes ──────────────────────────────────────────────────────

  defp safe_attrs(attrs) do
    Enum.flat_map(attrs, fn {name, value} ->
      name = String.downcase(name)

      cond do
        name == "style" -> style_attr(value)
        name in @url_attrs -> if safe_url?(value), do: [{name, value}], else: []
        name in @attrs -> [{name, value}]
        true -> []
      end
    end)
  end

  defp safe_url?(value) do
    url = value |> String.trim() |> String.downcase()

    # Only the part before the first /, ? or # can carry a scheme; a colon after
    # that is just a query value, not something to be suspicious of.
    scheme = url |> String.split(~r{[/?#]}, parts: 2) |> hd()

    cond do
      not String.contains?(scheme, ":") -> true
      String.starts_with?(url, "data:image/") -> true
      true -> Enum.any?(@schemes, &String.starts_with?(scheme, &1 <> ":"))
    end
  end

  defp style_attr(value) do
    case value |> String.split(";") |> Enum.flat_map(&declaration/1) do
      [] -> []
      kept -> [{"style", Enum.join(kept, "; ")}]
    end
  end

  defp declaration(decl) do
    with [prop, val] <- String.split(decl, ":", parts: 2),
         prop = prop |> String.trim() |> String.downcase(),
         val = String.trim(val),
         true <- prop in @style_props,
         true <- safe_value?(val) do
      ["#{prop}: #{val}"]
    else
      _ -> []
    end
  end

  # `url()` would fetch, `expression()` and `javascript:` would execute, and a
  # backslash is how those get smuggled past a plain substring check.
  defp safe_value?(val) do
    down = String.downcase(val)

    not Enum.any?(
      ["url(", "expression", "javascript:", "@import", "\\"],
      &String.contains?(down, &1)
    )
  end

  defp escape(html) do
    html |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end
end
