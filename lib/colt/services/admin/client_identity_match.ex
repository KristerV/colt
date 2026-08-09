defmodule Colt.Services.Admin.ClientIdentityMatch do
  @moduledoc """
  Works out who a registered client is in our own data.

  Clients arrive through Liid's own outreach, so more often than not we already
  hold them as an enriched `Person`: name, title, phone, and the registry
  `Company` behind them. Matching is on the **sign-up address** against every
  Person we ever enriched — no campaign is named in code, and it keeps working
  whichever campaign (or owner) found them.

  Returns `{:ok, %{person: p, company: c}}` on a hit, `{:ok, nil}` otherwise.
  """

  alias Colt.Resources.Person

  def run(%{email: email}) do
    with {:ok, person} <- find_person(to_string(email)) do
      {:ok, describe(person)}
    end
  end

  defp find_person(email) do
    case Person.find_by_email(email, authorize?: false) do
      {:ok, [person | _]} -> {:ok, person}
      {:ok, []} -> {:ok, nil}
      {:error, _} -> {:ok, nil}
    end
  end

  defp describe(nil), do: nil
  defp describe(person), do: %{person: person, company: person.company}
end
