defmodule Colt.Services.Ai.Complete do
  @moduledoc """
  OpenRouter chat-completion call. Single seam for every LLM request — every
  call is recorded via `Colt.Services.Costs.Track`.

  ## Usage

      Colt.Services.Ai.Complete.run(:cheap, "Say hi")
      Colt.Services.Ai.Complete.run(:smart, [%{role: "user", content: "..."}],
        system: "You are a helpful assistant.",
        response_format: :json,
        max_tokens: 1024,
        temperature: 0.0,
        campaign_id: cid
      )

  ## Models

    * `:cheap` → GLM 4.7 (`z-ai/glm-4.7`)
    * `:smart` → Claude 4.5 Sonnet (`anthropic/claude-sonnet-4.5`)

  ## Caching

  When `system:` is supplied and the underlying model supports prompt caching
  (Anthropic), a `cache_control: %{type: "ephemeral"}` breakpoint is attached
  to the system message so the same system prompt across calls reuses the cache.

  ## Response

      {:ok, %{
        content: "...",       # raw string, or parsed map when response_format: :json
        input_tokens: 124,
        output_tokens: 56,
        cost_usd: 0.0008,
        cached: false,
        model: "anthropic/claude-sonnet-4.5"
      }}
      | {:error, reason}
  """
  require Logger

  alias Colt.Services.Costs.Track

  @endpoint "https://openrouter.ai/api/v1/chat/completions"
  @model_map %{
    cheap: "z-ai/glm-4.7",
    smart: "anthropic/claude-sonnet-4.5"
  }
  @retry_statuses [408, 429, 500, 502, 503, 504]

  def run(model_alias, prompt_or_messages, opts \\ []) do
    model = Map.fetch!(@model_map, model_alias)
    messages = build_messages(prompt_or_messages, opts, model_alias)

    body = %{
      model: model,
      messages: messages,
      usage: %{include: true}
    }

    body =
      body
      |> maybe_put(:max_tokens, opts[:max_tokens])
      |> maybe_put(:temperature, opts[:temperature])
      |> maybe_put_response_format(opts[:response_format], opts[:schema])

    started = System.monotonic_time(:millisecond)
    result = post(body)
    latency_ms = System.monotonic_time(:millisecond) - started

    handle_result(result, %{
      model: model,
      response_format: opts[:response_format],
      campaign_id: opts[:campaign_id],
      latency_ms: latency_ms
    })
  end

  defp build_messages(prompt_or_messages, opts, model_alias) do
    user_messages =
      case prompt_or_messages do
        prompt when is_binary(prompt) -> [%{role: "user", content: prompt}]
        list when is_list(list) -> list
      end

    case opts[:system] do
      nil -> user_messages
      system -> [system_message(system, model_alias) | user_messages]
    end
  end

  defp system_message(system, :smart) do
    # Anthropic prompt caching via OpenRouter — attach cache_control so the
    # system block becomes a cacheable prefix.
    %{
      role: "system",
      content: [
        %{type: "text", text: system, cache_control: %{type: "ephemeral"}}
      ]
    }
  end

  defp system_message(system, _alias), do: %{role: "system", content: system}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_response_format(map, nil, _), do: map

  defp maybe_put_response_format(map, :json, nil),
    do: Map.put(map, :response_format, %{type: "json_object"})

  defp maybe_put_response_format(map, :json, schema) when is_map(schema) do
    Map.put(map, :response_format, %{
      type: "json_schema",
      json_schema: %{name: "response", strict: true, schema: schema}
    })
  end

  defp post(body) do
    api_key = Application.fetch_env!(:colt, :openrouter)[:api_key]

    Req.post(@endpoint,
      headers: [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ],
      json: body,
      receive_timeout: 60_000,
      retry: fn _req, resp_or_err ->
        case resp_or_err do
          %Req.Response{status: status} when status in @retry_statuses -> true
          %{__exception__: true} -> true
          _ -> false
        end
      end,
      max_retries: 1
    )
  end

  defp handle_result({:ok, %Req.Response{status: 200, body: body}}, ctx) do
    choice = body |> Map.fetch!("choices") |> List.first()
    raw = choice |> Map.fetch!("message") |> Map.fetch!("content")

    content =
      case ctx.response_format do
        :json -> Jason.decode!(raw)
        _ -> raw
      end

    usage = Map.get(body, "usage", %{})
    input_tokens = Map.get(usage, "prompt_tokens")
    output_tokens = Map.get(usage, "completion_tokens")
    cost_usd = Map.get(usage, "cost") || Map.get(usage, "total_cost") || 0
    cached = (Map.get(usage, "prompt_tokens_details") || %{}) |> Map.get("cached_tokens", 0) > 0

    Track.run(%{
      provider: :openrouter,
      model: ctx.model,
      status: :ok,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cost_usd: to_decimal(cost_usd),
      latency_ms: ctx.latency_ms,
      cached: cached,
      campaign_id: ctx.campaign_id
    })

    {:ok,
     %{
       content: content,
       input_tokens: input_tokens,
       output_tokens: output_tokens,
       cost_usd: to_decimal(cost_usd),
       cached: cached,
       model: ctx.model
     }}
  end

  defp handle_result({:ok, %Req.Response{status: status, body: body}}, ctx) do
    err = "openrouter http #{status}: #{inspect(body)}"
    track_error(ctx, err)
    {:error, err}
  end

  defp handle_result({:error, exception}, ctx) do
    err = Exception.message(exception)
    track_error(ctx, err)
    {:error, err}
  end

  defp track_error(ctx, err) do
    Track.run(%{
      provider: :openrouter,
      model: ctx.model,
      status: :error,
      latency_ms: ctx.latency_ms,
      error: String.slice(err, 0, 500),
      campaign_id: ctx.campaign_id
    })
  end

  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_binary(n), do: Decimal.new(n)
  defp to_decimal(_), do: Decimal.new(0)
end
