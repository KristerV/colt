defmodule Colt.Services.Costs.Track do
  @moduledoc """
  The single seam every paid external API call funnels through. Inserts one
  `Colt.Resources.ApiCall` row. Never raises — logging a cost must not break
  the calling service.
  """
  require Logger

  alias Colt.Resources.ApiCall

  def run(attrs) when is_map(attrs) do
    case ApiCall.record(attrs) do
      {:ok, record} ->
        {:ok, record}

      {:error, reason} ->
        Logger.warning("Costs.Track failed: #{inspect(reason)}; attrs=#{inspect(attrs)}")
        {:error, reason}
    end
  end
end
