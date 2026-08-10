defmodule Colt.Services.Export.ThreadTranscript do
  @moduledoc """
  One contact's conversation → plain text you can paste into a chat AI.

  On screen the timeline carries its meaning in markup: who sent what is a
  colour and a side of the pane, the state of a send is a chip, bodies are
  HTML. Pasted into a text-only assistant all of that is gone. So this renders
  the *same* timeline as labelled blocks — a header saying who the contact is,
  then one delimited, numbered block per email / note / status event in the
  order they happened, each one saying out loud what the UI says visually.

  Bodies go through `HtmlToText`, and their quoted history is dropped
  (`SplitQuote`): the quote is already in the transcript as the earlier
  message, and repeating it under every reply is most of the paste.

  Takes the contact and the timeline `FunnelThread.build_timeline/4` already
  built for the pane, so nothing is queried twice. Returns `{:ok, text}`.
  """

  alias Colt.Resources.StatusEvent
  alias Colt.Services.Email.HtmlToText
  alias Colt.Services.Email.SplitQuote

  def run(contact, timeline, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with {:ok, header} <- header(contact, now),
         {:ok, blocks} <- blocks(timeline) do
      {:ok, Enum.join([header | blocks], "\n\n") <> "\n"}
    end
  end

  # ── Header ──────────────────────────────────────────────────────────

  defp header(contact, now) do
    person = loaded(Map.get(contact, :person))
    company = person && loaded(Map.get(person, :company))

    lines =
      [
        "CONVERSATION TRANSCRIPT (exported from Liid on #{stamp(now)})",
        "Contact: #{name(person)}#{title_suffix(person)}",
        person && person.email && "Email: #{person.email}",
        person && person.phone && "Phone: #{person.phone}",
        company && "Company: #{company.name}#{website_suffix(company)}",
        outcome_line(contact),
        next_action_line(contact),
        "",
        "Entries are in chronological order. US = the person exporting this " <>
          "transcript, THEM = the contact. Internal notes were never sent."
      ]
      |> Enum.reject(&(&1 in [nil, false]))

    {:ok, Enum.join(lines, "\n")}
  end

  defp name(%{name: name}) when is_binary(name) and name != "", do: name
  defp name(_), do: "(unnamed)"

  defp title_suffix(%{title: title}) when is_binary(title) and title != "", do: " — #{title}"
  defp title_suffix(_), do: ""

  defp website_suffix(%{website_url: url}) when is_binary(url) and url != "", do: " (#{url})"
  defp website_suffix(_), do: ""

  defp outcome_line(%{outcome: :won}), do: "Outcome: WON"
  defp outcome_line(%{outcome: :lost}), do: "Outcome: LOST"
  defp outcome_line(_), do: nil

  defp next_action_line(%{outcome: nil, next_action_at: %DateTime{} = at}),
    do: "Next action due: #{Calendar.strftime(at, "%Y-%m-%d")}"

  defp next_action_line(_), do: nil

  # ── Blocks ──────────────────────────────────────────────────────────

  defp blocks(timeline) do
    {:ok, timeline |> Enum.with_index(1) |> Enum.map(fn {item, n} -> block(item, n) end)}
  end

  defp block(%{kind: :note} = item, n) do
    """
    --- [#{n}] #{stamp(item.at)} · INTERNAL NOTE (not sent to the contact) ---
    #{String.trim(item.note.body || "")}\
    """
  end

  defp block(%{kind: :status} = item, n) do
    reason = event_reason(item.event)

    """
    --- [#{n}] #{stamp(item.at)} · STATUS · #{event_label(item.event)} (by #{actor(item.event)}) ---#{reason && "\n" <> reason}\
    """
  end

  defp block(%{kind: :inbound} = item, n) do
    email = item.email

    """
    --- [#{n}] #{stamp(item.at)} · EMAIL · THEM → US · from #{email.from_address} ---
    Subject: #{email.subject || "(none)"}

    #{body(email.body)}\
    """
  end

  defp block(%{kind: kind} = item, n) when kind in [:outbound, :manual_outbound] do
    email = item.email

    origin =
      if kind == :manual_outbound,
        do: "manual reply",
        else: "sequence step #{(email.step_position || 0) + 1}"

    """
    --- [#{n}] #{stamp(item.at)} · EMAIL · US → THEM · #{origin} · #{email.status} ---
    Subject: #{email.user_subject || email.ai_subject || "(none)"}

    #{body(email.user_body || email.ai_body)}\
    """
  end

  # ── Bits ────────────────────────────────────────────────────────────

  defp body(raw) do
    {:ok, text} = HtmlToText.run(raw)
    {:ok, %{body: body}} = SplitQuote.run(text)

    case String.trim(body) do
      "" -> "(empty body)"
      trimmed -> trimmed
    end
  end

  # A draft that is neither sent nor scheduled has no moment in time.
  defp stamp(nil), do: "no date"
  defp stamp(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  defp event_label(%{kind: :checklist} = event) do
    mark = if StatusEvent.checklist_done?(event), do: "x", else: " "
    "checklist [#{mark}] #{event.to}"
  end

  defp event_label(%{kind: :entry}), do: "entered the sales funnel"

  defp event_label(%{kind: kind, from: from, to: to}) when is_binary(from) and is_binary(to),
    do: "#{kind}: #{from} → #{to}"

  defp event_label(%{kind: kind, to: to}) when is_binary(to), do: "#{kind}: → #{to}"
  defp event_label(%{kind: kind}), do: to_string(kind)

  defp event_reason(%{kind: kind}) when kind in [:checklist, :entry], do: nil
  defp event_reason(%{reason: reason}) when is_binary(reason) and reason != "", do: reason
  defp event_reason(_), do: nil

  defp actor(%{actor: %{email: email}}) when not is_nil(email), do: to_string(email)
  defp actor(_), do: "system"

  defp loaded(%Ash.NotLoaded{}), do: nil
  defp loaded(other), do: other
end
