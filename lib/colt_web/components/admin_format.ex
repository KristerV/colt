defmodule ColtWeb.Components.AdminFormat do
  @moduledoc """
  The stat box and the number/date formatting shared by the admin client pages.
  Calm Pro: white bounded card, faint uppercase label, big tabular number.
  """

  use Phoenix.Component

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :sub, :string, default: nil
  attr :class, :string, default: nil

  def stat(assigns) do
    ~H"""
    <div class="bg-card border border-border rounded-[11px] p-4" style="box-shadow:var(--shadow)">
      <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55">{@label}</div>
      <div class={[
        "text-[27px] font-bold tabular-nums leading-none tracking-[-0.02em] mt-2",
        @class || "text-ink"
      ]}>
        {@value}
      </div>
      <div :if={@sub} class="text-[11px] text-ink55 mt-1.5">{@sub}</div>
    </div>
    """
  end

  # --- money ----------------------------------------------------------------

  @doc "Unsigned dollars, two decimals: `$9.07`."
  def money(value), do: "$" <> decimals(value)

  @doc "Signed dollars with the sign outside the symbol: `-$9.07`, `+$18.00`."
  def signed(%Decimal{} = d) do
    cond do
      Decimal.negative?(d) -> "-$" <> decimals(Decimal.abs(d))
      Decimal.compare(d, 0) == :eq -> "$0.00"
      true -> "+$" <> decimals(d)
    end
  end

  def signed(value), do: value |> to_decimal() |> signed()

  def profit_class(%Decimal{} = d) do
    cond do
      Decimal.negative?(d) -> "text-red"
      Decimal.compare(d, 0) == :gt -> "text-green"
      true -> "text-ink55"
    end
  end

  def profit_class(value), do: value |> to_decimal() |> profit_class()

  defp decimals(value),
    do: value |> to_decimal() |> Decimal.round(2) |> Decimal.to_string(:normal)

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp to_decimal(_), do: Decimal.new(0)

  # --- counts ---------------------------------------------------------------

  def int(nil), do: "—"

  def int(n) when is_integer(n),
    do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, " ")

  def int(%Decimal{} = d), do: d |> Decimal.round(0) |> Decimal.to_integer() |> int()
  def int(_), do: "—"

  # --- time -----------------------------------------------------------------

  def date(nil), do: "—"
  def date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
  def date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
  def date(_), do: "—"

  @doc "Relative age, coarse on purpose: `just now`, `4h ago`, `12d ago`."
  def ago(nil), do: "never"

  def ago(stamp) do
    seconds = DateTime.diff(DateTime.utc_now(), as_datetime(stamp), :second)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end

  defp as_datetime(%DateTime{} = dt), do: dt
  defp as_datetime(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")

  # --- subscription ---------------------------------------------------------

  def status_class(:active), do: "text-green font-medium"
  def status_class(:past_due), do: "text-amber font-medium"
  def status_class(:canceled), do: "text-ink40 line-through"
  def status_class(_), do: "text-ink55"
end
