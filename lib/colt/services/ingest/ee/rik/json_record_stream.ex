defmodule Colt.Services.Ingest.Ee.Rik.JsonRecordStream do
  @moduledoc """
  Streams top-level objects out of a JSON-array file without loading the whole
  file into memory. Built for the rik.ee `yldandmed.json` dump (~4.4 GB).

  Walks the underlying binary by byte offset (via `:binary.at/2`) and slices
  each record out with `:binary.part/3` (an O(1) sub-binary reference, no
  copy). The buffer is compacted between records so memory stays bounded by
  the largest single record plus one chunk.
  """

  @chunk 65_536

  @doc """
  Returns `{:ok, stream}` for a JSON file whose top level is an array of
  objects.

  ## Options

    * `:decode` (default `true`) — when `true`, each element is a decoded map.
      When `false`, each element is the **raw object binary** (`"{...}"`).
      Letting the consumer peek a leading field via regex and decide whether
      to `Jason.decode!/1` saves the decode + nested-walk cost for records
      filtered out by sampling.
  """
  def run(path, opts \\ []) when is_binary(path) do
    if File.exists?(path) do
      decode? = Keyword.get(opts, :decode, true)
      {:ok, stream(path, decode?)}
    else
      {:error, {:not_found, path}}
    end
  end

  defp stream(path, decode?) do
    Stream.resource(
      fn -> init(path, decode?) end,
      &next_record/1,
      fn %{io: io} -> File.close(io) end
    )
  end

  defp init(path, decode?) do
    io = File.open!(path, [:read, :binary])

    %{io: io, buf: "", pos: 0, eof?: false, decode?: decode?}
    |> consume_array_start()
  end

  defp consume_array_start(state) do
    state = skip_ws(state)
    {c, state} = peek(state)

    case c do
      ?[ -> %{state | pos: state.pos + 1}
      _ -> raise "JsonRecordStream: expected '[' at top level"
    end
  end

  defp next_record(state) do
    state =
      state
      |> compact()
      |> skip_ws_and_commas()

    {c, state} = peek(state)

    case c do
      :eof ->
        {:halt, state}

      ?] ->
        {:halt, state}

      ?{ ->
        start = state.pos
        state = seek_to_object_end(state, 0, false, false)
        raw = :binary.part(state.buf, start, state.pos - start)
        {[maybe_decode(raw, state.decode?)], state}

      byte ->
        raise "JsonRecordStream: unexpected byte #{inspect(<<byte>>)} at top level"
    end
  end

  defp peek(state) do
    state = ensure_byte(state)

    cond do
      state.pos < byte_size(state.buf) ->
        {:binary.at(state.buf, state.pos), state}

      state.eof? ->
        {:eof, state}

      true ->
        peek(state)
    end
  end

  defp ensure_byte(%{pos: pos, buf: buf} = state) when pos < byte_size(buf), do: state
  defp ensure_byte(%{eof?: true} = state), do: state
  defp ensure_byte(state), do: refill(state)

  defp refill(%{eof?: true} = state), do: state

  defp refill(%{io: io, buf: buf} = state) do
    case IO.binread(io, @chunk) do
      :eof -> %{state | eof?: true}
      {:error, reason} -> raise "JsonRecordStream read error: #{inspect(reason)}"
      data -> %{state | buf: buf <> data}
    end
  end

  defp compact(%{pos: 0} = state), do: state

  defp compact(%{buf: buf, pos: pos} = state) do
    %{state | buf: :binary.part(buf, pos, byte_size(buf) - pos), pos: 0}
  end

  defp skip_ws(state) do
    {c, state} = peek(state)

    if c in [?\s, ?\n, ?\r, ?\t],
      do: skip_ws(%{state | pos: state.pos + 1}),
      else: state
  end

  defp skip_ws_and_commas(state) do
    {c, state} = peek(state)

    if c in [?\s, ?\n, ?\r, ?\t, ?,],
      do: skip_ws_and_commas(%{state | pos: state.pos + 1}),
      else: state
  end

  defp seek_to_object_end(state, depth, in_str?, esc?) do
    {c, state} = peek(state)

    case c do
      :eof ->
        raise "JsonRecordStream: unexpected EOF inside record (depth #{depth})"

      byte ->
        {nd, ns?, ne?} = step(byte, depth, in_str?, esc?)
        new_state = %{state | pos: state.pos + 1}

        if nd == 0,
          do: new_state,
          else: seek_to_object_end(new_state, nd, ns?, ne?)
    end
  end

  defp step(?", depth, true, true), do: {depth, true, false}
  defp step(?", depth, true, false), do: {depth, false, false}
  defp step(?", depth, false, _), do: {depth, true, false}
  defp step(?\\, depth, true, false), do: {depth, true, true}
  defp step(_, depth, true, _), do: {depth, true, false}
  defp step(?{, depth, false, _), do: {depth + 1, false, false}
  defp step(?}, depth, false, _), do: {depth - 1, false, false}
  defp step(_, depth, false, _), do: {depth, false, false}

  defp maybe_decode(raw, true), do: Jason.decode!(raw)
  defp maybe_decode(raw, false), do: raw
end
