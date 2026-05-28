defmodule ColtWeb.Plugs.StripeBodyReader do
  @moduledoc """
  Custom `Plug.Parsers` body reader that caches the raw request body for
  the Stripe webhook path so the signature can be re-verified after
  parsing. Other paths pass through untouched.
  """

  @stripe_path "/webhooks/stripe"

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, maybe_cache(conn, body)}

      {:more, body, conn} ->
        {:more, body, maybe_cache(conn, body)}

      other ->
        other
    end
  end

  defp maybe_cache(%Plug.Conn{request_path: @stripe_path} = conn, body) do
    existing = conn.assigns[:raw_body] || ""
    Plug.Conn.assign(conn, :raw_body, existing <> body)
  end

  defp maybe_cache(conn, _body), do: conn
end
