defmodule Colt.AppSettings do
  @moduledoc """
  Thin facade over `Colt.Resources.AppSetting`. Read/write site-wide
  singleton settings without dealing with the resource directly.
  """

  alias Colt.Resources.AppSetting

  @tracking_domain_key "tracking_domain"

  @doc "Site-wide tracking CNAME or `nil` if unset."
  @spec tracking_domain() :: String.t() | nil
  def tracking_domain, do: get(@tracking_domain_key)

  @spec put_tracking_domain(String.t() | nil) :: {:ok, AppSetting.t()} | {:error, term()}
  def put_tracking_domain(value) do
    put(@tracking_domain_key, normalize_domain(value))
  end

  @spec get(String.t()) :: String.t() | nil
  def get(key) when is_binary(key) do
    case AppSetting.get_by_key(key, authorize?: false) do
      {:ok, %AppSetting{value: v}} -> v
      _ -> nil
    end
  end

  @spec put(String.t(), String.t() | nil) :: {:ok, AppSetting.t()} | {:error, term()}
  def put(key, value) when is_binary(key) do
    AppSetting.upsert(key, value, authorize?: false)
  end

  defp normalize_domain(nil), do: nil

  defp normalize_domain(v) when is_binary(v) do
    case String.trim(v) do
      "" ->
        nil

      trimmed ->
        trimmed
        |> String.downcase()
        |> String.replace_prefix("https://", "")
        |> String.replace_prefix("http://", "")
    end
  end
end
