defmodule Colt.Deck.Transcode do
  @moduledoc """
  Normalise a freshly recorded clip to H.264/AAC before it is stored.

  Chromium on Linux ships without an H.264 *encoder*, so asking `MediaRecorder`
  for `video/mp4` gets you VP9+Opus wrapped in an MP4 container. That plays fine
  in Chrome and not at all in Safari — which is exactly the prospect opening the
  deck on an iPhone. The recorded container lies about its contents, so there is
  no way to detect the problem from the file name.

  Recording only ever happens on a dev machine, so this runs ffmpeg there and
  the artefact that gets committed is already universally playable. Prod never
  transcodes and needs no ffmpeg.

  Also downscales: the face bubble renders at roughly 150 CSS px, so storing
  720p is several megabytes of detail nobody sees. 540p keeps a full-frame intro
  shot sharp while cutting the file by ~5×.

  If ffmpeg can't do it, the clip is still stored as recorded — losing a take
  you just performed would be worse — and the studio raises the failure to the
  screen. There is no repair pass: fix ffmpeg and record the slide again.
  """

  require Logger

  @height 540
  @crf "26"

  @doc """
  Returns `{:ok, binary, content_type, note}` — `note` is nil on success or a
  human-readable reason the clip was stored as-recorded.
  """
  def run(binary, content_type) do
    with {:ok, ffmpeg} <- executable(),
         {:ok, input} <- write_temp(binary),
         {:ok, output} <- convert(ffmpeg, input) do
      converted = File.read!(output)
      File.rm(input)
      File.rm(output)

      {:ok, converted, "video/mp4", nil}
    else
      {:error, reason} ->
        Logger.warning("deck transcode skipped: #{reason}")
        {:ok, binary, content_type, reason}
    end
  end

  defp executable do
    case System.find_executable("ffmpeg") do
      nil ->
        {:error,
         "ffmpeg isn't installed, so this clip is stored in the browser's own codec — " <>
           "it may not play on iPhones. Install ffmpeg and record this slide again."}

      path ->
        {:ok, path}
    end
  end

  defp write_temp(binary) do
    path = Path.join(System.tmp_dir!(), "deck-#{System.unique_integer([:positive])}.src")

    case File.write(path, binary) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, "could not buffer the clip (#{inspect(reason)})"}
    end
  end

  defp convert(ffmpeg, input) do
    output = input <> ".mp4"

    args = [
      "-y",
      "-i",
      input,
      "-c:v",
      "libx264",
      "-preset",
      "veryfast",
      "-crf",
      @crf,
      # yuv420p and an even width are what make the file playable on phones.
      "-pix_fmt",
      "yuv420p",
      "-vf",
      "scale=-2:#{@height}",
      "-c:a",
      "aac",
      "-b:a",
      "128k",
      "-ac",
      "1",
      # Move the moov atom to the front so playback starts before the whole
      # file has downloaded.
      "-movflags",
      "+faststart",
      output
    ]

    case System.cmd(ffmpeg, args, stderr_to_stdout: true) do
      {_out, 0} ->
        {:ok, output}

      {out, status} ->
        File.rm(output)
        Logger.warning("ffmpeg exited #{status}: #{String.slice(out, -600, 600)}")

        {:error,
         "ffmpeg failed on this clip, so it's stored in the browser's own codec — " <>
           "it may not play on iPhones. See the server log, then record this slide again."}
    end
  end
end
