defmodule Colt.Services.Enrichment.ExtractGenericEmail do
  @moduledoc """
  Find a generic mailbox (info@, contact@, sales@, …) on the landing page's
  registrable domain. Regex over raw HTML — landing only, per spec §6.3.

  Two passes, because people are creative with shared-inbox prefixes — `tere@`,
  `pood@`, `kontor@` are all real shared inboxes and none are on any keyword list:

  1. **Keyword pass.** Known prefixes, free and deterministic. Covers the bulk.
  2. **AI pass**, only when the keyword pass misses. Collects *every* address on
     the company's own domain and asks `ClassifyEmailAddress` which are shared
     inboxes, keeping the first. A page whose only address is the founder's
     stays a miss — that's the owner rung's business, not this one.

  Returns the first match or nil.
  """

  alias Colt.Services.Enrichment.ClassifyEmailAddress

  # The obvious ones. The AI pass is what catches the tail, so this list exists
  # to avoid a model call on the common case, not to be exhaustive.
  @prefixes ~w(info contact hello sales hi kontakt myynti)

  # A page can list dozens of addresses; classifying them all would cost more
  # than the rung is worth. Ordered by appearance, so the cap keeps the ones
  # nearest the top of the page.
  @max_ai_candidates 8

  @doc """
  `opts` are forwarded to the classifier for cost attribution. Pass
  `:classifier` (an `fn email, opts -> {:ok, :personal | :generic} end`) to keep
  the AI pass out of a test — the keyword pass never needs it.
  """
  def run(html, host, opts \\ [])

  def run(html, host, opts) when is_binary(html) and is_binary(host) do
    case Regex.run(keyword_pattern(host), html) do
      [match | _] -> {:ok, String.downcase(match)}
      _ -> ai_pass(html, host, opts)
    end
  end

  def run(_, _, _), do: {:ok, nil}

  defp ai_pass(html, host, opts) do
    {classifier, opts} = Keyword.pop(opts, :classifier, &ClassifyEmailAddress.run/2)

    html
    |> candidates(host)
    |> Enum.find_value({:ok, nil}, fn email ->
      case classifier.(email, opts) do
        {:ok, :generic} -> {:ok, email}
        _ -> nil
      end
    end)
  end

  defp candidates(html, host) do
    host
    |> any_address_pattern()
    |> Regex.scan(html)
    |> Enum.map(fn [match | _] -> String.downcase(match) end)
    |> Enum.uniq()
    |> Enum.take(@max_ai_candidates)
  end

  defp keyword_pattern(host) do
    prefix_alt = Enum.join(@prefixes, "|")
    Regex.compile!("(?i)\\b(?:#{prefix_alt})@#{host_suffix(host)}")
  end

  defp any_address_pattern(host) do
    Regex.compile!("(?i)\\b[a-z0-9._%+-]+@#{host_suffix(host)}")
  end

  # Same-host constraint as before: the address must sit on the company's own
  # registrable domain (subdomains allowed), never a third party's.
  defp host_suffix(host) do
    "(?:[a-z0-9-]+\\.)*#{Regex.escape(host_base(host))}\\b"
  end

  defp host_base(host) do
    host
    |> String.downcase()
    |> String.replace_prefix("www.", "")
  end
end
