defmodule Colt.Services.Sending.EmailWriterDraftsTest do
  @moduledoc """
  Which rows the writer puts on a thread, on the empty-pool path (no model
  call). Two invariants that duplicate cards in the editor when broken:

    * the OOO welcome-back always gets a row, even though the model only
      writes one once the admin has authored a first — otherwise the golden
      card has nothing to bind to and can never be authored in
    * a position that already holds a live (approved/sent) email is never
      re-drafted, so re-opening an approved contact can't lay a second
      sequence over the live one
  """
  use Colt.DataCase, async: false

  alias Ash.Seed
  alias Colt.Accounts.User

  alias Colt.Resources.{
    Campaign,
    CampaignContact,
    Company,
    EmailAccount,
    OutboundEmail,
    Person,
    Sequence,
    SequenceStep,
    Thread
  }

  alias Colt.Services.Sending.EmailWriter

  test "seeds a row for every email step plus the OOO welcome-back" do
    %{contact: contact, sequence: sequence} = graph()

    {:ok, _} = EmailWriter.run(contact, sequence_id: sequence.id, actor: nil)

    assert positions(contact) == [-1, 0, 1, 2]
  end

  test "the seeded welcome-back is blank, so the feature stays off until authored" do
    %{contact: contact, sequence: sequence} = graph()

    {:ok, _} = EmailWriter.run(contact, sequence_id: sequence.id, actor: nil)

    ooo = row_at(contact, SequenceStep.ooo_position())
    assert ooo.status == :drafted
    assert ooo.user_body == nil
  end

  test "never re-drafts a position that already holds a live email" do
    %{contact: contact, sequence: sequence} = graph()

    {:ok, _} = EmailWriter.run(contact, sequence_id: sequence.id, actor: nil)

    contact
    |> rows()
    |> Enum.each(&OutboundEmail.mark_approved!(&1, authorize?: false))

    # Re-opening the contact runs the writer again; the live rows must survive
    # alone rather than gaining a second, drafted twin at each position.
    {:ok, _} = EmailWriter.run(contact, sequence_id: sequence.id, actor: nil)

    assert positions(contact) == [-1, 0, 1, 2]
    assert Enum.map(rows(contact), & &1.status) |> Enum.uniq() == [:approved]
  end

  defp rows(contact) do
    thread = Thread.for_contact!(contact.id, authorize?: false)

    OutboundEmail.list_for_thread!(thread.id, authorize?: false)
  end

  defp positions(contact), do: contact |> rows() |> Enum.map(& &1.step_position) |> Enum.sort()

  defp row_at(contact, position),
    do: contact |> rows() |> Enum.find(&(&1.step_position == position))

  # A template with the admin OOO step and no user-edited history, so the
  # writer takes the empty-pool path and never calls the model.
  defp graph do
    n = System.unique_integer([:positive])
    user = Seed.seed!(User, %{email: "owner-#{n}@liid.app"})
    company = Seed.seed!(Company, %{name: "Acme #{n}", registry_code: "EE#{n}", market: :ee})

    person =
      Seed.seed!(Person, %{name: "Mart Tamm", email: "mart-#{n}@acme.ee", company_id: company.id})

    campaign = Seed.seed!(Campaign, %{name: "Camp #{n}", owner_id: user.id})

    inbox =
      Seed.seed!(EmailAccount, %{
        user_id: user.id,
        provider: :imap,
        address: "send-#{n}@liid.app",
        tz: "Europe/Tallinn",
        daily_quota: 50,
        status: :healthy
      })

    sequence = Seed.seed!(Sequence, %{campaign_id: campaign.id, name: "T#{n}", language: "et"})

    Enum.each(
      [{-1, :ooo, 0}, {0, :email, 0}, {1, :email, 2}, {2, :email, 2}, {3, :terminal, 7}],
      fn {position, kind, delay_days} ->
        Seed.seed!(SequenceStep, %{
          sequence_id: sequence.id,
          position: position,
          kind: kind,
          delay_days: delay_days
        })
      end
    )

    contact =
      Seed.seed!(CampaignContact, %{
        campaign_id: campaign.id,
        person_id: person.id,
        status: :sending,
        assigned_email_account_id: inbox.id
      })

    Seed.seed!(Thread, %{campaign_contact_id: contact.id})

    %{contact: contact, sequence: sequence, inbox: inbox}
  end
end
