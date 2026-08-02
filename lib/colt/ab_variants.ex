defmodule Colt.ABVariants do
  @moduledoc """
  A/B variants for the demo deck and the onboarding that follows it.

  `ab_funnel` assigns one variant per visitor (cookie, 1 year) for the whole
  site, so the same key that picks the deck length also drives whatever we
  branch on later in onboarding — one test, not two.

  The deck's slide order per variant lives in `ColtWeb.Deck.Slides.order/1`.
  """
  use AbFunnel.Variants

  def variants do
    [
      %{key: :features, label: "Features — the product tour", active: true},
      %{key: :solving_emails, label: "Solving emails — deliverability angle", active: true}
    ]
  end
end
