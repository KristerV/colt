defmodule Colt.Markets do
  @moduledoc """
  Canonical list of supported markets. Landing page and the campaign country
  picker both render from here.

  `enabled: false` markets are shown but greyed out / not clickable. Flip the
  flag once the corresponding ingest has populated rows in prod.
  """

  @markets [
    %{
      code: "EE",
      name: "Estonia",
      api: "rik.ee",
      market: :ee,
      enabled: true,
      job: Colt.Jobs.Ingest.Ee
    },
    %{
      code: "FI",
      name: "Finland",
      api: "ytj.fi",
      market: :fi,
      enabled: true,
      job: Colt.Jobs.Ingest.Fi
    },
    %{
      code: "LV",
      name: "Latvia",
      api: "ur.gov.lv",
      market: :lv,
      enabled: true,
      job: Colt.Jobs.Ingest.Lv
    },
    %{
      code: "LT",
      name: "Lithuania",
      api: "registrucentras.lt",
      market: :lt,
      enabled: true,
      job: Colt.Jobs.Ingest.Lt
    },
    %{
      code: "DK",
      name: "Denmark",
      api: "datacvr.dk",
      market: :dk,
      enabled: true,
      job: Colt.Jobs.Ingest.Dk
    },
    %{
      code: "SE",
      name: "Sweden",
      api: "bolagsverket.se",
      market: :se,
      enabled: false,
      job: Colt.Jobs.Ingest.Se
    },
    %{
      code: "NO",
      name: "Norway",
      api: "brreg.no",
      market: :no,
      enabled: true,
      job: Colt.Jobs.Ingest.No
    }
  ]

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
end
