defmodule Colt.Services.Enrichment.ExtractGenericEmail do
  @moduledoc """
  Find a generic mailbox (info@, contact@, sales@, …) on the landing page's
  registrable domain. Regex over raw HTML — landing only, per spec §6.3.

  Returns the first match or nil.
  """

  @prefixes ~w(info contact hello sales hi kontakt myynti)

  def run(html, host) when is_binary(html) and is_binary(host) do
    case Regex.run(pattern(host), html) do
      [match | _] -> {:ok, String.downcase(match)}
      _ -> {:ok, nil}
    end
  end

  def run(_, _), do: {:ok, nil}

  defp pattern(host) do
    base = host_base(host)
    prefix_alt = Enum.join(@prefixes, "|")
    Regex.compile!("(?i)\\b(?:#{prefix_alt})@(?:[a-z0-9-]+\\.)*#{Regex.escape(base)}\\b")
  end

  defp host_base(host) do
    host
    |> String.downcase()
    |> String.replace_prefix("www.", "")
  end
end
