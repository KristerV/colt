defmodule Colt.Services.Enrichment.Broadcast do
  @moduledoc """
  PubSub helpers for the enrichment pipeline. Phase 5 (funnel view) subscribes;
  Phase 4b workers publish via these helpers.

  Topic: `"campaign:" <> campaign_id`. Messages:

    * `{:stage, campaign_company_id, stage_atom, state_atom}` — pipeline stage moved.
      `stage_atom` ∈ `:website | :icp | :contact`.
      `state_atom` ∈ `:idle | :work | :done | :skip | :fall | :fail`.
    * `{:row, campaign_company_id, patch_map}` — row-level field changes
      (status, contact name/title, error).
  """

  alias Phoenix.PubSub

  @pubsub Colt.PubSub

  @stages ~w(website icp contact)a
  @states ~w(idle work done skip fall fail)a

  def stage(campaign_id, campaign_company_id, stage, state)
      when stage in @stages and state in @states do
    PubSub.broadcast(@pubsub, topic(campaign_id), {:stage, campaign_company_id, stage, state})
  end

  def row(campaign_id, campaign_company_id, patch) when is_map(patch) do
    PubSub.broadcast(@pubsub, topic(campaign_id), {:row, campaign_company_id, patch})
  end

  def topic(campaign_id), do: "campaign:#{campaign_id}"

  def subscribe(campaign_id), do: PubSub.subscribe(@pubsub, topic(campaign_id))
end
