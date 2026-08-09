defmodule Colt.Resources.CampaignContact.Calculations.SalesBucket do
  @moduledoc """
  Which bucket a contact falls into on the sales funnel board.

  The board's columns are *derived*, never typed by hand. Exactly two fields
  decide it — `outcome` and `next_action_at`:

    * `:won` / `:lost` — an outcome is set; the conversation is closed.
    * `:later`         — next action is dated after today.
    * `:now`           — everything else: dated today, overdue, or never
                         given a date at all.

  An untriaged contact (no date) lands in `:now` on purpose. Nothing is
  allowed to sit in the funnel invisibly.

  Computed in Elixir rather than SQL so "today" resolves in the funnel's
  timezone (`Colt.SalesClock`) and matches the chips the board renders.
  """
  use Ash.Resource.Calculation

  alias Colt.SalesClock

  @impl true
  def load(_query, _opts, _context), do: [:outcome, :next_action_at]

  @impl true
  def calculate(records, _opts, _context) do
    today = SalesClock.today()
    Enum.map(records, &bucket(&1, today))
  end

  defp bucket(%{outcome: outcome}, _today) when outcome in [:won, :lost], do: outcome
  defp bucket(%{next_action_at: nil}, _today), do: :now

  defp bucket(%{next_action_at: at}, today) do
    if Date.after?(SalesClock.to_local_date(at), today), do: :later, else: :now
  end
end
