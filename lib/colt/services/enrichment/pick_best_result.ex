defmodule Colt.Services.Enrichment.PickBestResult do
  @moduledoc """
  Given Google search results for a company, ask GLM 4.7 which (if any) is
  the company's official site. Returns `{:ok, url | :none}`.
  """

  alias Colt.Services.Ai.Complete
  alias Colt.Services.Search.Google.Result

  @system """
  You match a company name + region to the most likely OFFICIAL website from a list of search results.
  Reject results that are aggregators, registries, social media, news, or LinkedIn pages.
  Return JSON only.
  """

  @schema %{
    type: "object",
    additionalProperties: false,
    required: ["url"],
    properties: %{
      url: %{type: ["string", "null"]}
    }
  }

  def run(company, results, opts \\ [])

  def run(_company, [], _opts), do: {:ok, :none}

  def run(company, results, opts) when is_list(results) do
    listing =
      results
      |> Enum.take(10)
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {%Result{title: t, url: u, snippet: s}, i} ->
        "#{i}. #{u}\n   title: #{t}\n   snippet: #{s}"
      end)

    user = """
    Company: #{company.name}
    Region: #{company.region || "—"}
    Industry: #{company.industry_code || "—"}

    Search results:
    #{listing}

    Return {"url": "<best>"} or {"url": null} if none is the official site.
    """

    case Complete.run(:cheap, user,
           system: @system,
           response_format: :json,
           schema: @schema,
           campaign_id: opts[:campaign_id],
           subject: opts[:subject],
           task: "pick_best_result"
         ) do
      {:ok, %{content: %{"url" => url}}} when is_binary(url) and url != "" -> {:ok, url}
      {:ok, _} -> {:ok, :none}
      {:error, _} = err -> err
    end
  end
end
