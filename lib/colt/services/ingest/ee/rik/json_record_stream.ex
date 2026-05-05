defmodule Colt.Services.Ingest.Ee.Rik.JsonRecordStream do
  @moduledoc """
  Streams top-level objects out of a JSON-array file without loading the whole
  file into memory. Built for the rik.ee `yldandmed.json` dump (~4.4 GB).

  Tolerates any whitespace / indentation. Uses brace-counting with explicit
  string-literal and escape handling.
  """

  @chunk 65_536

  @doc """
  Returns `{:ok, stream_of_decoded_maps}` for a JSON file whose top level is
  an array of objects.
  """
  def run(path) when is_binary(path) do
    with true <- File.exists?(path) || {:error, {:not_found, path}} do
      {:ok, stream(path)}
    end
  end

  defp stream(path) do
    Stream.resource(
      fn -> init(path) end,
      &next_record/1,
      fn %{io: io} -> File.close(io) end
    )
  end

  defp init(path) do
    io = File.open!(path, [:read, :binary])
    %{io: io, buf: "", eof?: false} |> consume_array_start()
  end

  defp consume_array_start(state) do
    state = trim_ws(state)

    case state.buf do
      "[" <> rest -> %{state | buf: rest}
      _ -> raise "JsonRecordStream: expected '[' at top level"
    end
  end

  defp next_record(state) do
    state = state |> trim_ws() |> trim_commas() |> trim_ws()

    case state.buf do
      "]" <> _ ->
        {:halt, state}

      "" ->
        if state.eof?, do: {:halt, state}, else: next_record(refill(state))

      "{" <> _ ->
        {json, state} = collect_object(state, [], 0, false, false)
        {[Jason.decode!(json)], state}
    end
  end

  defp trim_ws(state) do
    state = if state.buf == "" and not state.eof?, do: refill(state), else: state

    case state.buf do
      <<c, rest::binary>> when c in [?\s, ?\n, ?\r, ?\t] ->
        trim_ws(%{state | buf: rest})

      _ ->
        state
    end
  end

  defp trim_commas(state) do
    case state.buf do
      "," <> rest -> trim_commas(%{state | buf: rest} |> trim_ws())
      _ -> state
    end
  end

  defp refill(%{eof?: true} = state), do: state

  defp refill(%{io: io} = state) do
    case IO.binread(io, @chunk) do
      :eof -> %{state | eof?: true}
      {:error, reason} -> raise "JsonRecordStream read error: #{inspect(reason)}"
      data -> %{state | buf: state.buf <> data}
    end
  end

  defp collect_object(%{buf: ""} = state, acc, depth, in_str?, esc?) do
    state = refill(state)

    if state.eof? and state.buf == "" do
      raise "JsonRecordStream: unexpected EOF inside record (depth #{depth})"
    else
      collect_object(state, acc, depth, in_str?, esc?)
    end
  end

  defp collect_object(%{buf: <<c::utf8, rest::binary>>} = state, acc, depth, in_str?, esc?) do
    {new_depth, new_in_str?, new_esc?} = step(c, depth, in_str?, esc?)
    new_acc = [acc | <<c::utf8>>]
    state = %{state | buf: rest}

    if new_depth == 0 do
      {IO.iodata_to_binary(new_acc), state}
    else
      collect_object(state, new_acc, new_depth, new_in_str?, new_esc?)
    end
  end

  # Buffer ends mid-codepoint (multi-byte UTF-8 split across chunks). Refill.
  defp collect_object(%{eof?: false} = state, acc, depth, in_str?, esc?) do
    collect_object(refill(state), acc, depth, in_str?, esc?)
  end

  defp collect_object(%{buf: buf}, _acc, depth, _in_str?, _esc?) do
    raise "JsonRecordStream: invalid trailing bytes #{inspect(buf)} at depth #{depth}"
  end

  defp step(?", depth, true, true), do: {depth, true, false}
  defp step(?", depth, true, false), do: {depth, false, false}
  defp step(?", depth, false, _), do: {depth, true, false}
  defp step(?\\, depth, true, false), do: {depth, true, true}
  defp step(_, depth, true, _), do: {depth, true, false}
  defp step(?{, depth, false, _), do: {depth + 1, false, false}
  defp step(?}, depth, false, _), do: {depth - 1, false, false}
  defp step(_, depth, false, _), do: {depth, false, false}
end
