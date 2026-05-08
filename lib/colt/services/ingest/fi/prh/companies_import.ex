defmodule Colt.Services.Ingest.Fi.Prh.CompaniesImport do
  @moduledoc """
  Streams the PRH `/all_companies` ZIP straight from `unzip -p`'s stdout,
  splitting the top-level JSON array into individual objects on the fly,
  decoding each, and bulk-upserting through `Company.upsert_full`.

  The shape on disk is `[{...},{...},...]` on a single 1.4 GB line.
  `jq -c '.[]'` OOMs on it; `jq --stream` is constant-memory but slow.
  Walking bytes via a brace/string state machine is fastest and costs
  zero deps.
  """

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @batch 500
  @zip "all_companies.zip"

  def run do
    with {:ok, path} <- locate_file(),
         {:ok, count} <- stream_and_upsert(path) do
      {:ok, %{file: @zip, processed: count}}
    end
  end

  defp locate_file do
    dir = Application.fetch_env!(:colt, :prh_fi_cache_dir)
    path = Path.join(dir, @zip)
    if File.exists?(path), do: {:ok, path}, else: {:error, {:not_found, path}}
  end

  defp stream_and_upsert(path) do
    count =
      path
      |> unzip_stream()
      |> split_objects()
      |> Progress.tick("PRH companies rows read")
      |> Stream.map(&parse_object/1)
      |> Stream.reject(&is_nil/1)
      |> Stream.filter(&active_when_sampling/1)
      |> Stream.filter(&Sample.included?(&1.registry_code))
      |> Stream.chunk_every(@batch)
      |> Enum.reduce(0, fn chunk, n ->
        Ash.bulk_create!(chunk, Company, :upsert_full,
          return_errors?: true,
          stop_on_error?: true
        )

        n + length(chunk)
      end)

    Progress.done("PRH companies upserted", count)
    {:ok, count}
  end

  # ---- unzip stdout as a binary chunk stream ----

  defp unzip_stream(zip_path) do
    Stream.resource(
      fn -> open_unzip(zip_path) end,
      &read_chunk/1,
      &close_port/1
    )
  end

  defp open_unzip(zip_path) do
    exe = System.find_executable("unzip") || raise "unzip binary not found on PATH"

    Port.open(
      {:spawn_executable, exe},
      [:binary, :exit_status, :stream, :hide, args: ["-p", zip_path]]
    )
  end

  defp read_chunk(port) do
    receive do
      {^port, {:data, data}} ->
        {[data], port}

      {^port, {:exit_status, 0}} ->
        {:halt, port}

      {^port, {:exit_status, n}} ->
        raise "unzip exited with status #{n}"
    after
      120_000 -> raise "unzip read timeout (120s without data)"
    end
  end

  defp close_port(port) do
    try do
      Port.close(port)
    catch
      :error, _ -> :ok
    end
  end

  # ---- top-level array → one JSON object per emitted binary ----
  # Walks bytes maintaining (brace depth, in-string?, escape-next?).
  # While depth == 0 we skip the array structure (`[`, `,`, `]`, ws).
  # Inside an object we accumulate; when depth returns to 0 we emit.

  def split_objects(chunks) do
    Stream.transform(
      chunks,
      fn -> %{buf: [], depth: 0, in_str: false, esc: false} end,
      &walk_chunk/2,
      fn _ -> :ok end
    )
  end

  defp walk_chunk(chunk, state) do
    walk(chunk, state, [])
  end

  defp walk(<<>>, state, acc), do: {Enum.reverse(acc), state}

  # Escape applies to the byte AFTER a backslash inside a string.
  defp walk(<<b, rest::binary>>, %{esc: true} = s, acc) do
    walk(rest, %{s | buf: [s.buf, b], esc: false}, acc)
  end

  # Inside a string: handle backslash and closing quote.
  defp walk(<<?\\, rest::binary>>, %{in_str: true} = s, acc) do
    walk(rest, %{s | buf: [s.buf, ?\\], esc: true}, acc)
  end

  defp walk(<<?", rest::binary>>, %{in_str: true} = s, acc) do
    walk(rest, %{s | buf: [s.buf, ?"], in_str: false}, acc)
  end

  defp walk(<<b, rest::binary>>, %{in_str: true} = s, acc) do
    walk(rest, %{s | buf: [s.buf, b]}, acc)
  end

  # Outside a string: structural bytes.
  defp walk(<<?", rest::binary>>, s, acc) do
    walk(rest, %{s | buf: [s.buf, ?"], in_str: true}, acc)
  end

  defp walk(<<?{, rest::binary>>, s, acc) do
    walk(rest, %{s | buf: [s.buf, ?{], depth: s.depth + 1}, acc)
  end

  defp walk(<<?}, rest::binary>>, s, acc) do
    new_depth = s.depth - 1
    new_buf = [s.buf, ?}]

    if new_depth == 0 do
      walk(rest, %{s | buf: [], depth: 0}, [IO.iodata_to_binary(new_buf) | acc])
    else
      walk(rest, %{s | buf: new_buf, depth: new_depth}, acc)
    end
  end

  # Outside a string AND outside any object: skip the array structure
  # (the leading `[`, the `,` separators, the trailing `]`, whitespace).
  defp walk(<<_b, rest::binary>>, %{depth: 0} = s, acc) do
    walk(rest, s, acc)
  end

  # Inside an object, outside a string: just accumulate.
  defp walk(<<b, rest::binary>>, s, acc) do
    walk(rest, %{s | buf: [s.buf, b]}, acc)
  end

  # ---- decode + map ----

  defp parse_object(json_binary) do
    case Jason.decode(json_binary) do
      {:ok, json} -> map_company(json)
      _ -> nil
    end
  end

  defp map_company(json) do
    with code when is_binary(code) <- get_in(json, ["businessId", "value"]),
         name when is_binary(name) <- pick_name(json["names"]) do
      %{
        registry_code: code,
        market: :fi,
        name: name,
        region: pick_city(json["addresses"]),
        status: derive_status(json),
        industry_code: get_in(json, ["mainBusinessLine", "type"]),
        website_url: pick_website(json["website"]),
        website_source: if(get_in(json, ["website", "url"]), do: :registry, else: nil)
      }
    else
      _ -> nil
    end
  end

  defp pick_name(nil), do: nil
  defp pick_name([]), do: nil

  defp pick_name(names) when is_list(names) do
    current =
      names
      |> Enum.filter(&is_nil(&1["endDate"]))
      |> Enum.sort_by(& &1["version"], :asc)
      |> List.first()

    name = (current || List.first(names))["name"]
    if is_binary(name) and name != "", do: name, else: nil
  end

  defp pick_city(nil), do: nil
  defp pick_city([]), do: nil

  defp pick_city(addresses) when is_list(addresses) do
    addresses
    |> Enum.filter(&is_nil(&1["endDate"]))
    |> Enum.sort_by(& &1["version"], :asc)
    |> List.first()
    |> case do
      nil -> nil
      addr -> addr["city"] || addr["postOffices"] |> get_first_city()
    end
  end

  defp get_first_city(nil), do: nil
  defp get_first_city([]), do: nil

  defp get_first_city(list) when is_list(list) do
    list
    |> Enum.find(&(&1["languageCode"] == "1"))
    |> case do
      nil -> List.first(list)["city"]
      entry -> entry["city"]
    end
  end

  defp pick_website(nil), do: nil

  defp pick_website(%{"url" => url}) when is_binary(url) and url != "" do
    if String.starts_with?(url, "http"), do: url, else: "https://" <> url
  end

  defp pick_website(_), do: nil

  # In dev (sampling on), drop ceased companies before applying the 3%
  # hash sample — otherwise the 60% deleted population dominates the
  # tiny sample and we end up with ~no active rows to test against. In
  # prod (no sampling) we ingest everything for historical lookups.
  defp active_when_sampling(%{status: :registered}), do: true
  defp active_when_sampling(_), do: not Sample.enabled?()

  # PRH's top-level `status` field is NOT aliveness — observed value 2 on
  # both active (Marimekko, no endDate) and ceased companies. The real
  # signals are `tradeRegisterStatus` (1=Registered, 4=Ceased) and
  # `endDate` (non-null = ceased).
  defp derive_status(json) do
    cond do
      json["endDate"] not in [nil, ""] -> :deleted
      json["tradeRegisterStatus"] == "1" -> :registered
      json["tradeRegisterStatus"] == "4" -> :deleted
      true -> :other
    end
  end
end
