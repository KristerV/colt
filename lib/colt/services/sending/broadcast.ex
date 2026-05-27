defmodule Colt.Services.Sending.Broadcast do
  @moduledoc """
  PubSub helpers for the sending engine. Topic mirrors the enrichment side:
  `"campaign:" <> campaign_id`.

  Messages:

    * `{:email_sent, email_id, contact_id, step_position}`
    * `{:email_failed, email_id, contact_id, reason}`
    * `{:email_skipped, email_id, contact_id, reason}` — panic / paused
    * `{:next_scheduled, email_id, contact_id, step_position}`
    * `{:inbound_received, email_id, contact_id}`
    * `{:reply_categorized, contact_id, category}`
    * `{:sequence_halted, contact_id, reason}`
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

  def inbound(campaign_id, email_id, contact_id),
    do:
      PubSub.broadcast(
        @pubsub,
        topic(campaign_id),
        {:inbound_received, email_id, contact_id}
      )

  def reply_categorized(campaign_id, contact_id, category),
    do:
      PubSub.broadcast(
        @pubsub,
        topic(campaign_id),
        {:reply_categorized, contact_id, category}
      )

  def sequence_halted(campaign_id, contact_id, reason),
    do:
      PubSub.broadcast(
        @pubsub,
        topic(campaign_id),
        {:sequence_halted, contact_id, reason}
      )

  def topic(campaign_id), do: "campaign:#{campaign_id}"

  def subscribe(campaign_id), do: PubSub.subscribe(@pubsub, topic(campaign_id))
end
