defmodule Colt.Services.Sending.BackfillTemplates do
  @moduledoc """
  One-off, manually-run backfill: label every user-edited opener across all
  campaigns with its outreach template (§6.2). Wraps
  `Colt.Services.Sending.LabelTemplate`.

  Runs synchronously and oldest-first per campaign so labels accumulate in
  the order the user actually wrote them — the same order the live trigger
  would have produced — instead of a recency-jumbled set. Only user-edited
  openers are labeled (an unedited opener is just the AI reusing a template).

  Idempotent-ish: by default it relabels everything. Pass
  `skip_labeled?: true` to only fill in openers that have no label yet.

      mix run -e 'Colt.Services.Sending.BackfillTemplates.run()'
      mix run -e 'Colt.Services.Sending.BackfillTemplates.run(skip_labeled?: true)'
      mix run -e 'Colt.Services.Sending.BackfillTemplates.run(campaign_id: "<uuid>")'
  """

  require Logger

  alias Colt.Resources.{Campaign, OutboundEmail}
  alias Colt.Services.Sending.LabelTemplate

  def run(opts \\ []) do
    skip_labeled? = Keyword.get(opts, :skip_labeled?, false)

    with {:ok, campaigns} <- load_campaigns(opts),
         {:ok, stats} <- label_campaigns(campaigns, skip_labeled?) do
      Logger.info("backfill_templates: done — #{inspect(stats)}")
      {:ok, stats}
    end
  end

  defp load_campaigns(opts) do
    case Keyword.get(opts, :campaign_id) do
      nil ->
        {:ok, Campaign.list_all_recent!(authorize?: false)}

      id ->
        with {:ok, campaign} <- Campaign.get(id, authorize?: false), do: {:ok, [campaign]}
    end
  end

  defp label_campaigns(campaigns, skip_labeled?) do
    stats =
      Enum.reduce(campaigns, %{labeled: 0, skipped: 0, failed: 0}, fn campaign, acc ->
        merge_stats(acc, label_campaign(campaign, skip_labeled?))
      end)

    {:ok, stats}
  end

  defp label_campaign(campaign, skip_labeled?) do
    openers =
      OutboundEmail.list_edited_openers_for_campaign!(campaign.id,
        load: [thread: [:campaign_contact]],
        authorize?: false
      )

    Enum.reduce(openers, %{labeled: 0, skipped: 0, failed: 0}, fn opener, acc ->
      cond do
        skip_labeled? and opener.template_label not in [nil, ""] ->
          bump(acc, :skipped)

        true ->
          label_one(opener, acc)
      end
    end)
  end

  defp label_one(opener, acc) do
    case LabelTemplate.run(opener) do
      {:ok, labeled} ->
        Logger.info("backfill_templates: #{opener.id} -> #{labeled.template_label}")
        bump(acc, :labeled)

      {:error, reason} ->
        Logger.warning("backfill_templates: #{opener.id} failed — #{inspect(reason)}")
        bump(acc, :failed)
    end
  end

  defp bump(acc, key), do: Map.update!(acc, key, &(&1 + 1))

  defp merge_stats(a, b), do: Map.merge(a, b, fn _k, x, y -> x + y end)
end
