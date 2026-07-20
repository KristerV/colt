defmodule Colt.Services.Email.SplitQuote do
  @moduledoc """
  Split plain-text email into the new message and the quoted history below it.

  Works on the output of `Colt.Services.Email.HtmlToText` — the markers are the
  ones mail clients write into the body: Outlook's `From:`/`Sent:`/`To:` header
  block, Gmail's "On … wrote:" attribution, the "Original Message" divider, a
  long underscore rule, or `>`-prefixed lines.

  Returns `{:ok, %{body: body, quoted: quoted_or_nil}}`. A message that is
  *entirely* quote (marker at position 0) is left whole in `:body`, since
  there'd be nothing left to show.
  """

  @markers [
    # ----- Original Message -----
    ~r/^[ \t]*-{2,}[ \t]*Original Message[ \t]*-{2,}/im,
    # Outlook: From: … followed by another header line
    ~r/^[ \t]*From:[ \t]\S.*\n(?:.*\n)?[ \t]*(?:Sent|To|Date|Subject):[ \t]/m,
    # Gmail-style attribution, incl. common non-English verbs
    ~r/^[ \t]*(?:On|Le|Am|El)[ \t].{0,200}\b(?:wrote|kirjutas|schrieb|a écrit|escribió):[ \t]*$/mu,
    # …and the variant where the verb line stands alone
    ~r/^[ \t]*.{0,200}\b(?:kirjutas|wrote)[ \t]*:[ \t]*$/mu,
    # Outlook's horizontal rule between reply and quote
    ~r/^[ \t]*_{10,}[ \t]*$/m,
    # Classic quote prefix
    ~r/^>.*$/m
  ]

  def run(text, _opts \\ [])

  def run(text, _opts) when is_binary(text) do
    case earliest_marker(text) do
      nil -> {:ok, %{body: String.trim(text), quoted: nil}}
      0 -> {:ok, %{body: String.trim(text), quoted: nil}}
      at -> {:ok, split_at(text, at)}
    end
  end

  def run(_text, _opts), do: {:ok, %{body: "", quoted: nil}}

  defp earliest_marker(text) do
    @markers
    |> Enum.flat_map(fn re ->
      case Regex.run(re, text, return: :index) do
        [{at, _len} | _] -> [at]
        _ -> []
      end
    end)
    |> Enum.min(fn -> nil end)
  end

  defp split_at(text, at) do
    body = text |> binary_part(0, at) |> String.trim()
    quoted = text |> binary_part(at, byte_size(text) - at) |> String.trim()

    # A marker in the first line or two usually means the "new" part is just a
    # greeting fragment of the quote — but if there's nothing above it at all,
    # keep the message whole rather than showing an empty card.
    if body == "", do: %{body: quoted, quoted: nil}, else: %{body: body, quoted: quoted}
  end
end
