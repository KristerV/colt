defmodule Colt.Services.Sending.Broadcast do
  @moduledoc """
  PubSub helpers for the sending engine. Topic mirrors the enrichment side:
  `"campaign:" <> campaign_id`.

  Messages:

    * `{:email_sent, email_id, contact_id, step_position}`
    * `{:email_failed, email_id, contact_id, reason}`
    * `{:email_skipped, email_id, contact_id, reason}` — panic / paused
    * `{:next_scheduled, email_id, contact_id, step_position}`
  """

  alias Phoenix.PubSub

  @pubsub Colt.PubSub

  def sent(campaign_id, email_id, contact_id, step_position),
    do:
      PubSub.broadcast(
        @pubsub,
        topic(campaign_id),
        {:email_sent, email_id, contact_id, step_position}
      )

  def failed(campaign_id, email_id, contact_id, reason),
    do:
      PubSub.broadcast(
        @pubsub,
        topic(campaign_id),
        {:email_failed, email_id, contact_id, reason}
      )

  def skipped(campaign_id, email_id, contact_id, reason),
    do:
      PubSub.broadcast(
        @pubsub,
        topic(campaign_id),
        {:email_skipped, email_id, contact_id, reason}
      )

  def next_scheduled(campaign_id, email_id, contact_id, step_position),
    do:
      PubSub.broadcast(
        @pubsub,
        topic(campaign_id),
        {:next_scheduled, email_id, contact_id, step_position}
      )

  def topic(campaign_id), do: "campaign:#{campaign_id}"

  def subscribe(campaign_id), do: PubSub.subscribe(@pubsub, topic(campaign_id))
end
