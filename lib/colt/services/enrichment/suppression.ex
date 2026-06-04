defmodule Colt.Services.Enrichment.Suppression do
  @moduledoc """
  Per-campaign "already contacted" domain suppression.

  Two roles:
    * upload side — scan an uploaded file (any text/CSV) for email addresses and
      reduce them to normalized, unique domains (`domains_from_text/1`). We don't
      care about separators, header rows, column count, or whether the address is
      bare (`me@x.com`) or wrapped (`Mister Krister <me@x.com>`) — a regex pulls
      every address out and the rest is ignored;
    * pipeline side — given a company's website URL, decide whether its domain is
      on the campaign's suppression list (`excluded?/2`).

  Normalization is shared by both sides so a `www.acme.com` website matches an
  `someone@acme.com` email: lowercase, strip a leading `www.`.
  """

  alias Colt.Resources.SuppressedDomain

  # Deliberately permissive: any run of address chars, an `@`, then a dotted
  # host. We don't validate deliverability here — we only need the domain.
  @email_re ~r/[\w.+\-']+@[\w\-]+(?:\.[\w\-]+)+/u

  @doc """
  Is this company's website domain on the campaign's suppression list?

  Returns `false` for a nil/blank/unparseable URL so the pipeline proceeds
  normally when there's nothing to match on.
  """
  def excluded?(campaign_id, url) do
    case domain_from_url(url) do
      nil ->
        false

      domain ->
        case SuppressedDomain.match(campaign_id, domain, authorize?: false) do
          {:ok, [_ | _]} -> true
          _ -> false
        end
    end
  end

  @doc """
  Extract the registrable host from a website URL: lowercase, `www.` stripped.
  Returns `nil` when there's no parseable host.
  """
  def domain_from_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> normalize(host)
      _ -> nil
    end
  end

  def domain_from_url(_), do: nil

  @doc """
  Scan an enumerable of text chunks (typically file lines) for email addresses
  and return their sorted, unique, normalized domains. Anything that isn't an
  email address — headers, names, phone numbers, separators — is ignored.
  """
  def domains_from_text(lines) do
    lines
    |> Stream.flat_map(&extract_emails/1)
    |> Stream.map(&domain_from_email/1)
    |> Stream.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp extract_emails(line) when is_binary(line) do
    @email_re |> Regex.scan(line) |> Enum.map(&hd/1)
  end

  defp extract_emails(_), do: []

  @doc "Extract the normalized domain from a single email string, or `nil`."
  def domain_from_email(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.split("@")
    |> case do
      [_local, domain] when domain != "" -> normalize(domain)
      _ -> nil
    end
  end

  def domain_from_email(_), do: nil

  defp normalize(host) do
    host
    |> String.trim()
    |> String.downcase()
    |> String.replace_prefix("www.", "")
    |> case do
      "" -> nil
      domain -> domain
    end
  end
end
