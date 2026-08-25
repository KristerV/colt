defmodule Colt.Services.Sending.NotifyReplyDiscordTest do
  @moduledoc """
  Pure decision-logic test — no network call. `Discord.Notify` no-ops
  (`{:ok, :skipped}`) whenever the webhook URL is unset, which it is by
  default in test config, so we only assert on `NotifyReplyDiscord`'s own
  return value (whether it decided to notify at all).
  """

  use ExUnit.Case, async: true

  alias Colt.Services.Sending.NotifyReplyDiscord

  @my_user_id "4f186d06-25d3-4c02-94e6-f10f188f4fe0"
  @someone_elses_id "00000000-0000-0000-0000-000000000000"

  defp contact(attrs) do
    Map.merge(
      %{
        campaign_id: "campaign-1",
        campaign: %{owner_id: @my_user_id, name: "Hunt"},
        in_funnel_sales?: false,
        person: %{name: "Jane Tamm", email: "jane@example.com"}
      },
      attrs
    )
  end

  test "notifies on a fresh :interested reply in one of my campaigns" do
    assert {:ok, :notified} = NotifyReplyDiscord.run(contact(%{}), :interested)
  end

  test "notifies on any reply once the contact is already in the sales funnel" do
    c = contact(%{in_funnel_sales?: true})
    assert {:ok, :notified} = NotifyReplyDiscord.run(c, :not_interested)
    assert {:ok, :notified} = NotifyReplyDiscord.run(c, :other)
  end

  test "stays quiet on a not_interested/other reply outside the sales funnel" do
    assert {:ok, :skipped} = NotifyReplyDiscord.run(contact(%{}), :not_interested)
    assert {:ok, :skipped} = NotifyReplyDiscord.run(contact(%{}), :other)
  end

  test "never fires for a campaign that isn't mine" do
    c = contact(%{campaign: %{owner_id: @someone_elses_id, name: "Hunt"}, in_funnel_sales?: true})

    assert {:ok, :not_mine} = NotifyReplyDiscord.run(c, :interested)
  end
end
