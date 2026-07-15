defmodule Colt.Services.Enrichment.ResolveOwnerEmail do
  @moduledoc """
  Find the owner's email address for a company.

  Today there is exactly one way to do this: the contact address the company
  filed with the business registry, *when that address names a person*. On the EE
  import that's ~49% of companies — and it costs no scraping at all, which is why
  the owner rung runs before the job-title rung.

  Step 2 of the owner rung — take the owner's *name* from the registry, construct
  `first@domain` / `first.last@domain`, and verify — is not built: we import no
  person names. See `docs/todo.md`. When it lands it belongs here, behind the
  same `run/2`.

  Returns `{:ok, email}` or `{:ok, nil}` when the company has no owner address we
  can reach.
  """

  alias Colt.Services.Enrichment.RegistryEmailKind

  def run(company, opts \\ []) do
    case RegistryEmailKind.run(company, opts) do
      {:ok, :personal} -> {:ok, company.registry_email}
      {:ok, _} -> {:ok, nil}
      {:error, _} = err -> err
    end
  end
end
