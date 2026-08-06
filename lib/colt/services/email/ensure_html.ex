defmodule Colt.Services.Email.EnsureHtml do
  @moduledoc """
  Coerce a stored email body to HTML.

  Bodies reach the timeline in three shapes: manual replies are Trix HTML,
  inbound mail is whatever the sender's client produced, and sequenced AI sends
  are stored as the plain text the writer generated (`SendOne` only converts on
  the way out to Nylas). Rendering the timeline as HTML means the plain ones
  need escaping and explicit line breaks — the `whitespace-pre-wrap` container
  that used to carry them can't be used once neighbouring cards hold real markup.

  Returns `{:ok, html}`.
  """

  # A real tag, not just a stray `<`. Plain AI copy says things like
  # "a < b" or quotes an address as <rene@example.com>; neither is markup, and
  # treating them as such would let the parser eat them.
  @html_tag ~r{<(?:/[a-z]|[a-z][a-z0-9]*[\s/>])}i

  def run(raw, _opts \\ [])

  def run(raw, _opts) when is_binary(raw) do
    if Regex.match?(@html_tag, raw), do: {:ok, raw}, else: {:ok, plain_to_html(raw)}
  end

  def run(_raw, _opts), do: {:ok, ""}

  defp plain_to_html(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace("\n", "<br>\n")
  end
end
