defmodule Colt.Locks do
  @moduledoc """
  Postgres advisory-lock helpers used to serialize work per host (and similar
  scopes) without coordinating processes. Backs the per-domain scrape lock from
  spec §6 — a transaction-scoped lock that auto-releases on commit/rollback.

      Colt.Locks.with_domain_lock("example.com", fn ->
        Colt.Services.Scrape.Fetch.run("https://example.com/about")
      end)
      # => {:ok, result} | :locked | {:error, term}
  """

  alias Colt.Repo

  @doc """
  Acquire a transaction-scoped advisory lock keyed on `hashtext(host)`. If the
  lock can't be acquired immediately, returns `:locked` so the caller can
  snooze. Otherwise runs `fun` inside the transaction and returns its result.
  """
  def with_domain_lock(host, fun) when is_binary(host) and is_function(fun, 0) do
    Repo.transaction(fn ->
      case Repo.query!("SELECT pg_try_advisory_xact_lock(hashtext($1))", [host]) do
        %Postgrex.Result{rows: [[true]]} -> fun.()
        _ -> Repo.rollback(:locked)
      end
    end)
    |> case do
      {:ok, value} -> {:ok, value}
      {:error, :locked} -> :locked
      {:error, other} -> {:error, other}
    end
  end
end
