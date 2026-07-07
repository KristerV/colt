defmodule Colt.Services.Sending.StatusLabel do
  @moduledoc """
  Human labels for reply/override outcomes, stored on a `StatusEvent`'s `to`
  field. Shared by the AI categorizer (`CategorizeReply`) and the manual
  "Mark as…" override (`ManualOverride`) so both paths write the identical
  string for the same outcome — edit the label once, both feeds agree.
  """

  @labels %{
    interested: "interested",
    not_interested: "not interested",
    ooo: "out of office",
    other: "other",
    call_ready: "call ready",
    no_reply: "no reply"
  }

  @doc "Stored label for a reply-category / manual-override atom."
  def label(outcome), do: Map.get(@labels, outcome, to_string(outcome))
end
