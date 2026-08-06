defmodule Colt.ABTests do
  @moduledoc """
  What Liid is A/B testing.

  One experiment today — the demo deck's two cuts — but `ab_funnel` buckets a
  visitor once *per experiment*, so a second test costs a second bucket rather
  than the four arms a combined `variants/0` list would have needed.

  Two declarations here do the work that used to be guesswork:

  - `entry: "deck_started"` — nobody is in the funnel until they press Play.
    Without it every browser holding a cookie counted, so a `signed_in` fired on
    the landing page by someone who never opened `/demo` showed up as a step with
    *more* people in it than the step above.
  - `steps: &steps/1` — the deck's own slide order, per cut, instead of the
    average position each event happened to land at. Slides nobody reached render
    as `0` rather than vanishing, which is the drop-off you actually want to see.
  """
  use AbFunnel.Experiments

  alias ColtWeb.Deck.Slides

  @key "deck"

  @doc "The experiment key deck events are filed under."
  def key, do: @key

  def experiments do
    [
      %{
        key: @key,
        label: "Demo deck",
        variants: [
          %{key: :features, label: "Features — the product tour"},
          %{key: :solving_emails, label: "Solving emails — deliverability angle"}
        ],
        entry: "deck_started",
        # Signing up, not leaving a phone number: the deck's job is accounts, and
        # `lead_submitted` only covers the prospects who took the call/message
        # branch of the closing slide. `campaign_created` is the stricter reading
        # if activation ever matters more than registration.
        goal: "signed_in",
        steps: {__MODULE__, :steps, 1}
      }
    ]
  end

  @doc """
  The funnel for one cut, in the order it is actually played.

  The cover is dropped because it is never tracked — `DeckLive` only starts
  counting slides once Play has moved the index off it.

  The tail is deliberately past the deck: `AbFunnel.LiveView` is mounted on the
  authenticated live_session too, so a viewer who registers and builds a campaign
  stays the same person in the same funnel. `lead_submitted` and `signed_in` are
  really two branches of the close rather than two rungs of one ladder — a linear
  chart can only show them in sequence, so read the gap between them as "took the
  other exit", not as drop-off.
  """
  def steps(variant) do
    slides =
      variant
      |> Slides.order()
      |> Enum.reject(&Slides.cover?/1)
      |> Enum.map(&"slide_#{&1}")

    ["deck_started"] ++
      slides ++
      ["deck_completed", "cta_clicked", "lead_submitted", "signed_in", "campaign_created"]
  end

  @doc "The human label for a variant key, for links and admin copy."
  def label(variant) when is_binary(variant) do
    case AbFunnel.Experiments.fetch(@key) do
      nil -> variant
      experiment -> AbFunnel.Experiment.variant_label(experiment, variant)
    end
  end
end
