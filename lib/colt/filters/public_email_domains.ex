defmodule Colt.Filters.PublicEmailDomains do
  @moduledoc """
  Free/public webmail domains (gmail.com, outlook.com, ...) that many unrelated
  people share, so a domain match on one of these proves nothing about identity.

  Used by `Colt.Services.Sending.IngestInbound`'s cross-domain reply fallback:
  matching a contact by "same domain as the inbound sender" is only safe on a
  company's own domain. On a public domain it would attach any stranger's
  email (e.g. a warmup ping) to whichever contact on gmail.com happened to be
  most recently updated for that inbox.
  """

  @domains ~w(
    gmail.com googlemail.com
    outlook.com hotmail.com live.com msn.com
    yahoo.com yahoo.co.uk ymail.com
    icloud.com me.com mac.com
    aol.com
    protonmail.com proton.me pm.me
    gmx.com gmx.net
    mail.com
    zoho.com
  )

  @spec public?(String.t() | nil) :: boolean()
  def public?(nil), do: false
  def public?(domain) when is_binary(domain), do: String.downcase(domain) in @domains
end
