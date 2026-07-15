defmodule Colt.Services.Enrichment.ResolveGenericInbox do
  @moduledoc """
  Find the company's shared mailbox (info@, contact@, …).

  Two sources, website first:

  1. `company.generic_email` — scraped off the landing page by
     `ExtractGenericEmail` during `FetchLanding`.
  2. `company.registry_email`, but only when it classifies `:generic`.

  The website wins because a site's published inbox is the address the company
  wants mail on *today*, whereas the registry copy is whatever they filed at
  incorporation and may be years stale. The registry is the fallback that keeps
  this rung alive for the ~93% of EE companies with no site to scrape.

  Returns `{:ok, email}` or `{:ok, nil}`.
  """

  alias Colt.Services.Enrichment.RegistryEmailKind

  def run(company, opts \\ [])

  def run(%{generic_email: email}, _opts) when is_binary(email) and email != "",
    do: {:ok, email}

  def run(company, opts) do
    case RegistryEmailKind.run(company, opts) do
      {:ok, :generic} -> {:ok, company.registry_email}
      {:ok, _} -> {:ok, nil}
      {:error, _} = err -> err
    end
  end
end
