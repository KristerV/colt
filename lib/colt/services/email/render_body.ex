defmodule Colt.Services.Email.RenderBody do
  @moduledoc """
  Stored email body → the HTML the funnel timeline renders, plus its quoted
  history.

  The stored body is never touched; this is display only. The order of the steps
  is load-bearing: the quote split reads `class`/`id` markers that sanitizing
  removes, so it has to happen first, on markup that is not yet safe to render.
  Nothing between here and the template puts either half on the page — both come
  back sanitized.

  Returns `{:ok, %{body: html, quoted: html_or_nil}}`, both safe for `raw/1`.
  """

  alias Colt.Services.Email.EnsureHtml
  alias Colt.Services.Email.SanitizeHtml
  alias Colt.Services.Email.SplitQuoteHtml

  def run(raw, _opts \\ []) do
    with {:ok, html} <- EnsureHtml.run(raw),
         {:ok, %{body: body, quoted: quoted}} <- SplitQuoteHtml.run(html),
         {:ok, safe_body} <- SanitizeHtml.run(body),
         {:ok, safe_quoted} <- SanitizeHtml.run(quoted) do
      {:ok, %{body: safe_body, quoted: safe_quoted}}
    end
  end
end
