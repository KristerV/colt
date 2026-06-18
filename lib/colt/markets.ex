defmodule Colt.Markets do
  @moduledoc """
  Canonical list of supported markets. Landing page and the campaign country
  picker both render from here.

  `enabled: false` markets are shown but greyed out / not clickable. Flip the
  flag once the corresponding ingest has populated rows in prod.
  """

  # `language` / `language_name` drive the writer's per-template language
  # picker — the offered languages are exactly the markets listed here (plus
  # English, prepended in `languages/0`).
  @markets [
    %{
      code: "EE",
      name: "Estonia",
      api: "rik.ee",
      market: :ee,
      enabled: true,
      language: "et",
      language_name: "Estonian",
      job: Colt.Jobs.Ingest.Ee
    },
    %{
      code: "FI",
      name: "Finland",
      api: "ytj.fi",
      market: :fi,
      enabled: true,
      language: "fi",
      language_name: "Finnish",
      job: Colt.Jobs.Ingest.Fi
    },
    %{
      code: "LV",
      name: "Latvia",
      api: "ur.gov.lv",
      market: :lv,
      enabled: true,
      language: "lv",
      language_name: "Latvian",
      job: Colt.Jobs.Ingest.Lv
    },
    %{
      code: "LT",
      name: "Lithuania",
      api: "registrucentras.lt",
      market: :lt,
      enabled: true,
      language: "lt",
      language_name: "Lithuanian",
      job: Colt.Jobs.Ingest.Lt
    },
    %{
      code: "DK",
      name: "Denmark",
      api: "datacvr.dk",
      market: :dk,
      enabled: true,
      language: "da",
      language_name: "Danish",
      job: Colt.Jobs.Ingest.Dk
    },
    %{
      code: "SE",
      name: "Sweden",
      api: "bolagsverket.se",
      market: :se,
      enabled: false,
      language: "sv",
      language_name: "Swedish",
      job: Colt.Jobs.Ingest.Se
    },
    %{
      code: "NO",
      name: "Norway",
      api: "brreg.no",
      market: :no,
      enabled: true,
      language: "nb",
      language_name: "Norwegian",
      job: Colt.Jobs.Ingest.No
    }
  ]

  @english {"en", "English"}

  def job_for(market) when is_atom(market) do
    case Enum.find(@markets, &(&1.market == market)) do
      %{job: job} -> job
      nil -> nil
    end
  end

  def all, do: @markets

  def enabled, do: Enum.filter(@markets, & &1.enabled)

  def atoms, do: Enum.map(@markets, & &1.market)

  def enabled_atoms, do: enabled() |> Enum.map(& &1.market)

  @doc """
  Offered drafting languages as `{code, label}` — English plus one per listed
  market, deduped by code. The template editor's language picker renders from
  this so the options always track the supported countries.
  """
  def languages do
    [@english | Enum.map(@markets, &{&1.language, &1.language_name})]
    |> Enum.uniq_by(&elem(&1, 0))
  end

  @doc "The default drafting language code for a market (English if unknown)."
  def language_for(market) when is_atom(market) do
    case Enum.find(@markets, &(&1.market == market)) do
      %{language: lang} -> lang
      nil -> "en"
    end
  end
end
