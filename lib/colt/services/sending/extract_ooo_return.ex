defmodule Colt.Services.Sending.ExtractOooReturn do
  @moduledoc """
  Pull the "back in office" date out of an out-of-office auto-reply.

  Returns `{:ok, %Date{}}` when a concrete return date is found, or
  `{:ok, nil}` when the reply names no usable date (or the model is
  unsure / errors). The caller decides the fallback delay.
  """

  require Logger

  alias Colt.Resources.InboundEmail
  alias Colt.Services.Ai.Complete

  def run(%InboundEmail{} = inbound) do
    with {:ok, raw} <- extract(inbound) do
      {:ok, parse_date(raw)}
    end
  end

  defp extract(inbound) do
    body = (inbound.body || "") |> strip_html() |> String.slice(0, 3000)
    subject = inbound.subject || ""
    today = Date.utc_today() |> Date.to_iso8601()

    user_message = """
    The message below is an out-of-office auto-reply. Find the date the person
    returns to the office / is reachable again. Resolve relative phrasing
    ("back on Monday", "until the 15th", "next week") against today's date:
    #{today}. Prefer the first working day they are back.

    Reply JSON only: {"return_date": "YYYY-MM-DD"} — use an empty string for
    return_date if no date is stated or it's too vague to pin down.

    Subject: #{subject}
    Body:
    #{body}
    """

    case Complete.run(:smart, user_message,
           system: system(),
           response_format: :json,
           schema: schema(),
           temperature: 0.0,
           max_tokens: 128,
           task: "extract_ooo_return",
           subject: {:inbound_email, inbound.id}
         ) do
      {:ok, %{content: %{"return_date" => date}}} when is_binary(date) ->
        {:ok, date}

      {:ok, other} ->
        Logger.warning("extract_ooo_return: unexpected response #{inspect(other)}")
        {:ok, ""}

      {:error, reason} ->
        Logger.warning("extract_ooo_return: ai error #{inspect(reason)}")
        {:ok, ""}
    end
  end

  defp schema do
    %{
      type: "object",
      additionalProperties: false,
      required: ["return_date"],
      properties: %{
        return_date: %{
          type: "string",
          description: "ISO8601 date (YYYY-MM-DD) of return, or empty string if none."
        }
      }
    }
  end

  defp system do
    """
    You extract a single return-to-office date from an out-of-office reply and
    output strict JSON with exactly one key: return_date. Be conservative — if
    the reply gives no concrete date, return an empty string rather than guess.
    """
  end

  defp parse_date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, %Date{} = d} -> d
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp strip_html(text) when is_binary(text) do
    text
    |> String.replace(~r{<br\s*/?>}i, "\n")
    |> String.replace(~r{<[^>]+>}, "")
    |> String.replace(~r{[ \t]+\n}, "\n")
  end

  defp strip_html(_), do: ""
end
