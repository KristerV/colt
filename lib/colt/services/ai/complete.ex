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

  alias Colt.Services.Ai.PauseOnCreditExhaustion
  alias Colt.Services.Costs.Track

  @endpoint "https://openrouter.ai/api/v1/chat/completions"
  @model_map %{
    cheap: "z-ai/glm-4.7",
    smart: "anthropic/claude-sonnet-4.5"
  }
  @retry_statuses [408, 429, 500, 502, 503, 504]
  @empty_response_retries 3
  @max_message_bytes 50_000

  def run(model_alias, prompt_or_messages, opts \\ []) do
    case attempt(model_alias, prompt_or_messages, opts) do
      {:error, "model returned empty response" <> _} when model_alias == :cheap ->
        # GLM 4.7 deterministically dead-ends on some inputs (reasoning never
        # produces visible content). Same-body retries don't help; escalate
        # to :smart for one final shot before giving up.
        Logger.warning("ai.complete: :cheap returned empty, escalating to :smart")
        attempt(:smart, prompt_or_messages, opts)

      other ->
        other
    end
  end

  defp attempt(model_alias, prompt_or_messages, opts) do
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
      |> maybe_put_reasoning(model_alias)

    {subject_type, subject_id} = subject_pair(opts[:subject])

    ctx = %{
      model: model,
      response_format: opts[:response_format],
      campaign_id: opts[:campaign_id],
      task: opts[:task],
      subject_type: subject_type,
      subject_id: subject_id,
      prompt: serialize_prompt(messages)
    }

    run_with_retries(body, ctx, @empty_response_retries)
  end

  defp subject_pair({type, id}) when is_atom(type), do: {type, id}
  defp subject_pair(_), do: {nil, nil}

  # Build the single string we persist as the audit prompt. Per-message cap
  # with middle-truncation so the head and tail of long markdown blobs stay
  # readable in the modal.
  defp serialize_prompt(messages) do
    messages
    |> Enum.map_join("\n\n", fn %{role: role} = m ->
      "[#{role}]\n" <> (m |> Map.get(:content) |> message_text() |> cap_bytes(@max_message_bytes))
    end)
  end

  defp message_text(text) when is_binary(text), do: text

  defp message_text(parts) when is_list(parts) do
    parts
    |> Enum.map(fn
      %{type: "text", text: t} -> t
      %{"type" => "text", "text" => t} -> t
      bin when is_binary(bin) -> bin
      _ -> ""
    end)
    |> Enum.join("")
  end

  defp message_text(_), do: ""

  defp cap_bytes(bin, max) when is_binary(bin) do
    if byte_size(bin) <= max do
      bin
    else
      head = max |> div(2) |> min(byte_size(bin))
      tail = max - head
      head_bin = binary_part(bin, 0, head)
      tail_bin = binary_part(bin, byte_size(bin) - tail, tail)
      omitted = byte_size(bin) - head - tail
      head_bin <> "\n…[truncated #{omitted} bytes]…\n" <> tail_bin
    end
  end

  defp run_with_retries(body, ctx, attempts_left) do
    started = System.monotonic_time(:millisecond)
    result = post(body)
    latency_ms = System.monotonic_time(:millisecond) - started

    case handle_result(result, Map.put(ctx, :latency_ms, latency_ms)) do
      {:error, "model returned empty response" <> _} when attempts_left > 1 ->
        Logger.warning(
          "ai.complete: empty response from #{ctx.model}, retrying (#{attempts_left - 1} left)"
        )

        run_with_retries(body, ctx, attempts_left - 1)

      other ->
        other
    end
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

  # GLM 4.7 (and the Google Gemini route OpenRouter sometimes picks for it) is
  # a reasoning model. For `:cheap` we use it as a classifier — pin reasoning
  # to the lowest tier so we don't burn tokens on chain-of-thought. We used to
  # pass "none" but Google's surface only accepts {high|low|medium|minimal};
  # "minimal" is the closest equivalent.
  defp maybe_put_reasoning(map, :cheap),
    do: Map.put(map, :reasoning, %{effort: "medium"})

  defp maybe_put_reasoning(map, _), do: map

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
    raw = choice |> Map.fetch!("message") |> Map.fetch!("content") |> extract_text()
    ctx = Map.put(ctx, :response, raw)

    with {:ok, content} <- parse_content(raw, ctx.response_format) do
      usage = Map.get(body, "usage", %{})
      finish_ok(content, usage, ctx)
    else
      {:error, err} ->
        track_error(ctx, err)
        {:error, err}
    end
  end

  defp handle_result({:ok, %Req.Response{status: 402, body: body}}, ctx) do
    err = "openrouter http 402 (insufficient credits): #{inspect(body)}"
    track_error(ctx, err)
    PauseOnCreditExhaustion.run(err)
    {:error, err}
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

  defp parse_content(raw, _format) when raw in [nil, ""],
    do: {:error, "model returned empty response (likely exhausted reasoning budget)"}

  defp parse_content(raw, :json) do
    cleaned = strip_code_fence(raw)

    case Jason.decode(cleaned) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, "model returned non-JSON content: #{String.slice(raw, 0, 500)}"}
    end
  end

  defp parse_content(raw, _), do: {:ok, raw}

  # Backup for the json_schema response_format: even with strict schema,
  # Claude/GLM occasionally wrap JSON in ```json … ``` fences. Strip them
  # before decoding so the caller never sees this quirk.
  defp strip_code_fence(raw) when is_binary(raw) do
    trimmed = String.trim(raw)

    case Regex.run(~r/\A```(?:json)?\s*\n?(.*?)\n?```\z/s, trimmed, capture: :all_but_first) do
      [inner] -> String.trim(inner)
      _ -> trimmed
    end
  end

  defp strip_code_fence(raw), do: raw

  defp finish_ok(content, usage, ctx) do
    input_tokens = Map.get(usage, "prompt_tokens")
    output_tokens = Map.get(usage, "completion_tokens")
    cost_usd = Map.get(usage, "cost") || Map.get(usage, "total_cost") || 0
    cached = (Map.get(usage, "prompt_tokens_details") || %{}) |> Map.get("cached_tokens", 0) > 0

    Track.run(%{
      provider: :openrouter,
      model: ctx.model,
      task: ctx.task,
      status: :ok,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cost_usd: to_decimal(cost_usd),
      latency_ms: ctx.latency_ms,
      cached: cached,
      campaign_id: ctx.campaign_id,
      prompt: ctx.prompt,
      response: Map.get(ctx, :response),
      subject_type: ctx.subject_type,
      subject_id: ctx.subject_id
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

  defp track_error(ctx, err) do
    Track.run(%{
      provider: :openrouter,
      model: ctx.model,
      task: ctx.task,
      status: :error,
      latency_ms: ctx.latency_ms,
      error: String.slice(err, 0, 500),
      campaign_id: ctx.campaign_id,
      prompt: ctx.prompt,
      response: Map.get(ctx, :response),
      subject_type: ctx.subject_type,
      subject_id: ctx.subject_id
    })
  end

  # Some providers return `content` as a list of typed parts (reasoning, text).
  # Concat the textual parts; ignore reasoning blocks.
  defp extract_text(content) when is_binary(content), do: content

  defp extract_text(parts) when is_list(parts) do
    parts
    |> Enum.filter(fn p -> Map.get(p, "type") == "text" end)
    |> Enum.map_join("", &Map.get(&1, "text", ""))
  end

  defp extract_text(nil), do: ""

  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_binary(n), do: Decimal.new(n)
  defp to_decimal(_), do: Decimal.new(0)
end
