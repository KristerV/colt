defmodule Colt.Services.Ingest.Sample do
  @moduledoc """
  Hash-based registry-code sampling for the ingest pipeline.

  Set `config :colt, :ingest_sample_rate, 0.03` in `config/dev.exs` to keep
  ~3% of companies (≈11k of 371k). Leave it unset (or `nil` / `0`) in prod
  to ingest everything.

  The predicate is deterministic — same dev set every run — and evenly spread
  across registry codes so industry / region / age mix is preserved.

  Apply the same filter at every stage (`CompaniesImport`, `CompanyDetails`,
  `AnnualReports`) so an `--from N` partial run stays internally consistent.
  """

  @resolution 1_000_000

  def included?(registry_code) do
    case rate() do
      nil -> true
      n when n in [0, 0.0] -> true
      r when is_number(r) and r > 0 and r < 1 -> hash_under?(registry_code, r)
      _ -> true
    end
  end

  @doc """
  True when sampling is on (dev). Ingest pipelines use this to gate
  dev-only filters (e.g. active-only) so the small sample isn't
  dominated by ceased shells. In prod returns false → no extra filtering.
  """
  def enabled? do
    case rate() do
      nil -> false
      n when n in [0, 0.0] -> false
      r when is_number(r) and r > 0 and r < 1 -> true
      _ -> false
    end
  end

  defp hash_under?(code, rate) do
    :erlang.phash2(to_string(code), @resolution) < trunc(rate * @resolution)
  end

  defp rate, do: Application.get_env(:colt, :ingest_sample_rate)
end
