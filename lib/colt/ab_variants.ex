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
      %{key: :long, label: "Long deck (6 slides)", active: true},
      %{key: :short, label: "Short deck (4 slides)", active: true}
    ]
  end
end
