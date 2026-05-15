defmodule Colt.Services.Search.Google do
  @moduledoc """
  Google Custom Search wrapper. One call returns up to 10 results. Every call
  is logged via `Colt.Services.Costs.Track`.

  Pricing: free tier covers 100 queries/day, then $5 per 1000 queries
  ($0.005/query). We log the marginal rate on every call — over a billing
  period it overstates by the free tier's worth, which is fine for a budget
  signal.
  """
  alias Colt.Services.Costs.Track

  @endpoint "https://www.googleapis.com/customsearch/v1"
  @cost_per_query Decimal.new("0.005")

  defmodule Result do
    @moduledoc false
    defstruct [:title, :url, :snippet]
  end

  def run(query, opts \\ []) when is_binary(query) do
    cfg = Application.fetch_env!(:colt, :google_cse)

    params = %{
      key: cfg[:api_key],
      cx: cfg[:engine_id],
      q: query,
      num: opts[:num] || 10
    }

    started = System.monotonic_time(:millisecond)
    result = Req.get(@endpoint, params: params, receive_timeout: 30_000)
    latency_ms = System.monotonic_time(:millisecond) - started

    {subject_type, subject_id} =
      case opts[:subject] do
        {type, id} when is_atom(type) -> {type, id}
        _ -> {nil, nil}
      end

    ctx = %{
      query: query,
      latency_ms: latency_ms,
      campaign_id: opts[:campaign_id],
      task: opts[:task],
      subject_type: subject_type,
      subject_id: subject_id
    }

    handle(result, ctx)
  end

  defp handle({:ok, %Req.Response{status: 200, body: body}}, ctx) do
    items = Map.get(body, "items", [])

    results =
      Enum.map(items, fn item ->
        %Result{
          title: Map.get(item, "title"),
          url: Map.get(item, "link"),
          snippet: Map.get(item, "snippet")
        }
      end)

    Track.run(%{
      provider: :google_cse,
      task: ctx.task,
      status: :ok,
      query: ctx.query,
      results_count: length(results),
      cost_usd: @cost_per_query,
      latency_ms: ctx.latency_ms,
      campaign_id: ctx.campaign_id,
      subject_type: ctx.subject_type,
      subject_id: ctx.subject_id
    })

    {:ok, results}
  end

  defp handle({:ok, %Req.Response{status: status, body: body}}, ctx) do
    err = "google_cse http #{status}: #{inspect(body)}"
    track_error(ctx, err)
    {:error, err}
  end

  defp handle({:error, exception}, ctx) do
    err = Exception.message(exception)
    track_error(ctx, err)
    {:error, err}
  end

  defp track_error(ctx, err) do
    Track.run(%{
      provider: :google_cse,
      task: ctx.task,
      status: :error,
      query: ctx.query,
      latency_ms: ctx.latency_ms,
      campaign_id: ctx.campaign_id,
      error: String.slice(err, 0, 500),
      subject_type: ctx.subject_type,
      subject_id: ctx.subject_id
    })
  end
end
