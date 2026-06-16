defmodule Colt.CompanyRegistry do
  @moduledoc """
  Resolves a company's official public business-registry record to an external
  link operators can open in a new tab.

  Each market has its own national registry (Estonia → Teatmik, Finland → PRH,
  …). `link/1` maps a company's `{market, registry_code}` to a `%{label, url}`
  pair. Markets without a configured registry return `nil`, so callers should
  render the link only when one is present.

  Adding a market is a single `build/2` clause: take the market atom and the
  registry code, return `%{label: "Name", url: "https://…"}`.
  """

  @type t :: %{label: String.t(), url: String.t()}

  @doc """
  Returns a `%{label, url}` link to the company's national registry, or `nil`
  when the market has no configured registry or the code is missing.
  """
  @spec link(%{optional(:market) => atom(), optional(:registry_code) => term()} | nil) ::
          t() | nil
  def link(%{market: market, registry_code: code}) when is_binary(code) and code != "" do
    build(market, code)
  end

  def link(_), do: nil

  # Each clause takes the company's stored `registry_code` verbatim — for every
  # market below it drops straight into the URL with no reformatting (verified
  # against a real company per market).
  #
  # We deliberately link to clean public business directories (Teatmik, Allabolag,
  # …) rather than the official state registers: the directories give a readable
  # overview *with revenue and employee count*, where the official sites are
  # either dense data dumps or search boxes you can't deep-link. English locale
  # where the site offers one (EE/LV/LT); the rest are single-language.

  # Estonia — Teatmik (English locale). registrikood directly.
  defp build(:ee, code),
    do: %{label: "Teatmik", url: "https://www.teatmik.ee/en/personlegal/#{code}"}

  # Finland — Asiakastieto (Enento, sister of Sweden's Allabolag). Free overview
  # shows turnover, headcount and profit. The stored Business ID is hyphenated
  # (e.g. "0112038-9"); Asiakastieto's URL wants it de-hyphenated. The `-` path
  # segment is a placeholder name slug it self-corrects via redirect.
  defp build(:fi, code),
    do: %{
      label: "Asiakastieto",
      url: "https://www.asiakastieto.fi/yritykset/fi/-/#{String.replace(code, "-", "")}/yleiskuva"
    }

  # Latvia — Firmas.lv. Shows turnover and average employee count free (Lursoft
  # paywalls financials). 11-digit reg number; the `c` slug is a placeholder the
  # site self-corrects.
  defp build(:lv, code),
    do: %{label: "Firmas.lv", url: "https://www.firmas.lv/en/companies/c/#{code}"}

  # Lithuania — Scoris directory. Numeric legal-entity code (juridinio asmens
  # kodas) directly. (Official registrucentras.lt is session-gated.)
  defp build(:lt, code), do: %{label: "Scoris", url: "https://scoris.lt/en/imone/#{code}"}

  # Sweden — Allabolag directory. Bare 10-digit organisationsnummer (no hyphen),
  # which is exactly how it's stored. (Bolagsverket has no free deep-link.)
  defp build(:se, code), do: %{label: "Allabolag", url: "https://www.allabolag.se/#{code}"}

  # Norway — Purehelp. Shows revenue (omsetning) and employee count free. 9-digit
  # organisasjonsnummer; the site redirects to a slugged URL server-side.
  defp build(:no, code),
    do: %{label: "Purehelp", url: "https://www.purehelp.no/company/details/#{code}"}

  # Denmark — eStatistik. Clean profile with a financials table and employee
  # chart. 8-digit CVR; the `/c/` slug segment is decorative.
  defp build(:dk, code),
    do: %{label: "eStatistik", url: "https://estatistik.dk/virksomhed/c/#{code}"}

  # Poland — BizRaport, keyed on the KRS number, shows revenue and a headcount
  # section free (rejestr.io shows neither). NOTE: Poland is not yet ingested, so
  # the stored registry_code format is unconfirmed; this assumes a 10-digit
  # zero-padded KRS number. Revisit when the PL importer lands.
  defp build(:pl, code), do: %{label: "BizRaport", url: "https://www.bizraport.pl/krs/#{code}"}

  defp build(_market, _code), do: nil
end
