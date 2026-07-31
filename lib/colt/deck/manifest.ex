defmodule Colt.Deck.Manifest do
  @moduledoc """
  The deck's narration index — `priv/deck/manifest.json`, checked into git, and
  the only record of what has been recorded.

  You record in dev. The manifest is how a recording crosses into prod: the
  studio rewrites this file on every record and delete, you commit it alongside
  the clips in `priv/static/media/deck/`, and playback reads it. Nothing is
  stored in the database, so there is no export step and nothing to keep in
  sync — commit the repo and the deck ships.

  Keys are the slide key (`"hook"`). One clip per slide, shared by every deck
  that plays it — the long and short decks differ in slide *order*, not in
  narration.
  """

  require Logger

  def path do
    Path.join([:code.priv_dir(:colt), "deck", "manifest.json"])
  end

  @doc "Slide key => narration entry. `%{}` when nothing is recorded."
  def read do
    with {:ok, body} <- File.read(path()),
         {:ok, %{"slides" => slides}} <- Jason.decode(body) do
      Map.new(slides, fn {key, entry} -> {key, decode(entry)} end)
    else
      {:error, :enoent} ->
        %{}

      other ->
        Logger.warning("deck manifest unreadable: #{inspect(other)}")
        %{}
    end
  end

  @doc "Merge one slide's entry into the file, leaving every other slide alone."
  def put(slide_key, entry) do
    read() |> Map.put(to_string(slide_key), entry) |> save()
  end

  @doc "Drop one slide's entry."
  def delete(slide_key) do
    read() |> Map.delete(to_string(slide_key)) |> save()
  end

  defp save(entries) do
    slides = Map.new(entries, fn {key, entry} -> {key, encode(entry)} end)
    body = Jason.encode!(%{slides: slides}, pretty: true)

    File.mkdir_p!(Path.dirname(path()))
    File.write!(path(), body <> "\n")

    :ok
  end

  defp decode(entry) do
    %{
      media_url: entry["url"],
      media_content_type: entry["content_type"],
      duration_ms: entry["duration_ms"],
      recorded_at: parse_time(entry["recorded_at"])
    }
  end

  defp encode(entry) do
    %{
      url: entry.media_url,
      content_type: entry.media_content_type,
      duration_ms: entry.duration_ms,
      recorded_at: entry.recorded_at && DateTime.to_iso8601(entry.recorded_at)
    }
  end

  # Entries recorded before the manifest carried a timestamp simply have none —
  # that is a clip with an unknown date, not an unreadable manifest.
  defp parse_time(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> at
      _ -> nil
    end
  end

  defp parse_time(_other), do: nil
end
