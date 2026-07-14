defmodule Colt.MarketsTest do
  use ExUnit.Case, async: true

  alias Colt.Markets

  defp crontab do
    {Oban.Plugins.Cron, opts} =
      Application.get_env(:colt, Oban)[:plugins]
      |> Enum.find(&match?({Oban.Plugins.Cron, _}, &1))

    opts[:crontab]
  end

  defp scheduled_jobs, do: crontab() |> Enum.map(&elem(&1, 1))

  defp scheduled_ingests, do: scheduled_jobs() |> Enum.filter(&(to_string(&1) =~ "Ingest"))

  test "every ingest runs on the same schedule" do
    times =
      crontab()
      |> Enum.filter(fn {_cron, job} -> to_string(job) =~ "Ingest" end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()

    assert times == ["0 3 1 * *"]
  end

  test "available markets are a subset of the declared ones" do
    assert Markets.available_atoms() -- Markets.atoms() == []
  end

  test "every market carrying an ingest job is scheduled — available or not" do
    for %{job: job, market: market} <- Markets.all(), job != nil do
      assert job in scheduled_jobs(),
             "#{market} declares #{inspect(job)} but nothing schedules it"
    end
  end

  test "a market ingests regardless of availability" do
    # The point of the derivation: a new registry fills up while still hidden.
    unavailable_with_job =
      Enum.filter(Markets.all(), &(&1.available == false and &1.job != nil))

    assert unavailable_with_job != [], "expected at least one hidden market with an ingest"

    for %{job: job} <- unavailable_with_job, do: assert(job in scheduled_jobs())
  end

  test "a market with no ingest job is not scheduled" do
    assert Enum.any?(Markets.all(), &(&1.job == nil)), "expected a market with no ingest yet"

    # Nothing to assert per-market — a market with no job contributes no crontab
    # entry at all, so the guard is that every scheduled ingest maps back to a
    # declared job (see "every scheduled ingest belongs to a declared market").
    jobs = Markets.all() |> Enum.map(& &1.job) |> Enum.reject(&is_nil/1)
    assert length(scheduled_ingests()) == length(jobs)
  end

  test "every scheduled ingest belongs to a declared market" do
    jobs = Markets.all() |> Enum.map(& &1.job) |> Enum.reject(&is_nil/1)

    for job <- scheduled_jobs(), to_string(job) =~ "Ingest" do
      assert job in jobs, "#{inspect(job)} is scheduled but no market declares it"
    end
  end
end
