defmodule Colt.Services.Export.ThreadTranscriptTest do
  @moduledoc """
  The transcript is read by a text-only AI, so what's pinned here is what makes
  it readable without markup: who each message is from, that notes were never
  sent, and that a reply doesn't drag its quoted history along.

  Pure over the timeline `FunnelThread.build_timeline/4` produces, so the
  fixtures are plain maps of that shape — no database.
  """
  use ExUnit.Case, async: true

  alias Colt.Services.Export.ThreadTranscript

  @now ~U[2026-08-10 12:00:00Z]

  defp contact(overrides \\ %{}) do
    Map.merge(
      %{
        outcome: nil,
        next_action_at: nil,
        person: %{
          name: "Rene Tamm",
          title: "CTO",
          email: "rene@acme.ee",
          phone: "+372 5123 4567",
          company: %{name: "Acme OÜ", website_url: "acme.ee"}
        }
      },
      overrides
    )
  end

  defp outbound(fields) do
    email =
      Map.merge(
        %{
          status: :sent,
          step_position: 0,
          is_manual_reply: false,
          ai_subject: nil,
          ai_body: nil,
          user_subject: nil,
          user_body: nil
        },
        fields
      )

    %{kind: :outbound, at: ~U[2026-07-01 09:12:00Z], email: email}
  end

  defp inbound(fields) do
    email =
      Map.merge(%{from_address: "rene@acme.ee", subject: nil, body: nil}, fields)

    %{kind: :inbound, at: ~U[2026-07-02 11:03:00Z], email: email}
  end

  test "labels who each message is from and numbers them in order" do
    timeline = [
      outbound(%{ai_subject: "Kas tasub rääkida?", ai_body: "Tere Rene"}),
      inbound(%{subject: "Re: Kas tasub rääkida?", body: "<p>Jah, huvitav.</p>"})
    ]

    assert {:ok, text} = ThreadTranscript.run(contact(), timeline, now: @now)

    assert text =~ "Contact: Rene Tamm — CTO"
    assert text =~ "Email: rene@acme.ee"
    assert text =~ "Company: Acme OÜ (acme.ee)"

    assert text =~ "[1] 2026-07-01 09:12 UTC · EMAIL · US → THEM · sequence step 1 · sent"
    assert text =~ "[2] 2026-07-02 11:03 UTC · EMAIL · THEM → US · from rene@acme.ee"

    # HTML never reaches the paste — the reply arrives as its text.
    assert text =~ "Jah, huvitav."
    refute text =~ "<p>"
  end

  test "a reply's quoted history is dropped — it's already in the transcript above" do
    timeline = [
      inbound(%{
        subject: "Re: hi",
        body: "Jah, huvitav.<br><br>On Wed, Jul 1, 2026 Krister wrote:<br>&gt; Tere Rene"
      })
    ]

    assert {:ok, text} = ThreadTranscript.run(contact(), timeline, now: @now)

    assert text =~ "Jah, huvitav."
    refute text =~ "Tere Rene"
  end

  test "an internal note says out loud that it was never sent" do
    timeline = [
      %{kind: :note, at: ~U[2026-07-02 11:30:00Z], note: %{body: "Wants pricing."}}
    ]

    assert {:ok, text} = ThreadTranscript.run(contact(), timeline, now: @now)

    assert text =~ "INTERNAL NOTE (not sent to the contact)"
    assert text =~ "Wants pricing."
  end

  test "status events carry their kind, state and who did it" do
    timeline = [
      %{
        kind: :status,
        at: ~U[2026-07-03 08:00:00Z],
        event: %{
          kind: :checklist,
          from: nil,
          to: "Demo booked",
          reason: "checked",
          actor: %{email: "krister@liid.ee"}
        }
      },
      %{
        kind: :status,
        at: ~U[2026-07-04 08:00:00Z],
        event: %{kind: :outcome, from: nil, to: "Won", reason: nil, actor: nil}
      }
    ]

    assert {:ok, text} = ThreadTranscript.run(contact(), timeline, now: @now)

    assert text =~ "STATUS · checklist [x] Demo booked (by krister@liid.ee)"
    assert text =~ "STATUS · outcome: → Won (by system)"
  end

  test "an unsent draft keeps its status and admits it has no date" do
    timeline = [outbound(%{status: :drafted, step_position: 1, ai_body: "Follow-up"}) | []]
    timeline = Enum.map(timeline, &%{&1 | at: nil})

    assert {:ok, text} = ThreadTranscript.run(contact(), timeline, now: @now)

    assert text =~ "[1] no date · EMAIL · US → THEM · sequence step 2 · drafted"
  end

  test "the outcome of a closed contact rides along in the header" do
    assert {:ok, text} = ThreadTranscript.run(contact(%{outcome: :won}), [], now: @now)

    assert text =~ "Outcome: WON"
    assert text =~ "exported from Liid on 2026-08-10 12:00 UTC"
  end
end
