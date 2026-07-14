defmodule Colt.Markets do
  @moduledoc """
  Reader over the canonical market list in `config :colt, :markets`.

  Config is the source of truth. Everything that needs to know which countries
  exist — the landing page, the campaign country picker, the `market` enum on
  `Colt.Resources.Company`, the contact form's select, `/admin/countries` —
  derives from here. Nothing re-lists countries anywhere else; if you find
  yourself typing `[:ee, :fi, ...]`, call this module instead.

  `available/0` is the list users are actually offered. A market that is
  declared but `available: false` keeps its enum slot and registry links (so
  existing rows stay valid) while staying out of the picker and greyed out on
  the landing.

  Read via `Application.compile_env/2`: the list lives in `config/config.exs`,
  which is compile-time config, and the `Company.market` enum needs the atoms at
  compile time. Elixir tracks the dependency and recompiles callers when the
  config changes.
  """

  @markets Application.compile_env(:colt, :markets, [])

  @english {"en", "English"}

  def all, do: @markets

  @doc "Markets offered to users — declared *and* flagged available in config."
  def available, do: Enum.filter(@markets, & &1.available)

  @doc "Every declared market atom, available or not. Drives the `market` enum."
  def atoms, do: Enum.map(@markets, & &1.market)

  def available_atoms, do: available() |> Enum.map(& &1.market)

  def get(market) when is_atom(market), do: Enum.find(@markets, &(&1.market == market))

  @doc "The ingest job module for a market, or nil if it has none yet."
  def job_for(market) when is_atom(market) do
    case get(market) do
      %{job: job} -> job
      nil -> nil
    end
  end

  @doc ~S"""
  Display label for a market, e.g. `"Estonia (EE)"`. Falls back to the upcased
  atom for a market present in the data but absent from config.
  """
  def label(market) when is_atom(market) do
    case get(market) do
      %{name: name, code: code} -> "#{name} (#{code})"
      nil -> market |> to_string() |> String.upcase()
    end
  end

  @doc """
  Offered drafting languages as `{code, label}` — English plus one per declared
  market, deduped by code. Covers unavailable markets too: drafting an email in
  Swedish is useful even while the Swedish registry is dark.
  """
  def languages do
    [@english | Enum.map(@markets, &{&1.language, &1.language_name})]
    |> Enum.uniq_by(&elem(&1, 0))
  end

  @doc "The default drafting language code for a market (English if unknown)."
  def language_for(market) when is_atom(market) do
    case get(market) do
      %{language: lang} -> lang
      nil -> "en"
    end
  end

  @doc "Drafting language for a set of markets: single market → its language, multiple/empty → English."
  def drafting_language([single]), do: language_for(single)
  def drafting_language(markets) when is_list(markets), do: "en"
end
