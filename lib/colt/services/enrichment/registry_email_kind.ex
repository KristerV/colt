defmodule Colt.Services.Enrichment.RegistryEmailKind do
  @moduledoc """
  Classify a company's registry contact address as `:personal` or `:generic`,
  caching the verdict on the company.

  Both contact rungs need this answer and would otherwise each pay for it: the
  owner rung wants the address when it's `:personal`, the generic-inbox rung
  wants it when it's `:generic`. The verdict is a pure function of the address,
  so it's cached on `Company.registry_email_kind` and shared across every
  campaign that ever touches the company.

  Returns `{:ok, :personal | :generic}`, or `{:ok, nil}` if there's no address.
  """

  alias Colt.Resources.Company
  alias Colt.Services.Enrichment.ClassifyEmailAddress

  def run(company, opts \\ [])

  def run(%{registry_email_kind: kind}, _opts) when kind in [:personal, :generic],
    do: {:ok, kind}

  def run(%{registry_email: email} = company, opts) when is_binary(email) and email != "" do
    with {:ok, kind} <- ClassifyEmailAddress.run(email, opts),
         {:ok, _company} <- Company.set_registry_email_kind(company, kind) do
      {:ok, kind}
    end
  end

  def run(_company, _opts), do: {:ok, nil}
end
