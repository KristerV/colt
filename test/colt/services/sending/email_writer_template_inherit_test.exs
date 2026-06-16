defmodule Colt.Services.Sending.EmailWriterTemplateInheritTest do
  @moduledoc """
  Pins template inheritance (§6.2): the writer commits to one template per
  contact, and the opener it writes must be labeled with that template at write
  time — so every AI-written opener carries a label, not just the user-edited
  ones the post-hoc classifier picks up.

  Tagged `:eval` — `EmailWriter.run` calls the live model to produce the
  subject/body. The assertion is deterministic regardless of that output: with
  a single template in the campaign the writer can only pick that one, so the
  opener must inherit its label. Run with `mix test --only eval`.
  """
  use Colt.DataCase, async: false

  @moduletag :eval

  alias Colt.Accounts.User

  alias Colt.Resources.{
    Campaign,
    CampaignContact,
    Company,
    OutboundEmail,
    Person,
    Sequence,
    Thread
  }

  alias Colt.Services.Sending.EmailWriter

  @template %{
    label: "export-expansion-demo",
    angle: "Domestic market is covered; the export potential is untapped.",
    ask: "Want to sell more into Finland/Sweden? 45s intro video?",
    offer: "Sensible sales tooling (not full AI) that finds contacts and sends mail.",
    subject: "Hakkepuidu turg Eestis ja naabruskonnas",
    body: """
    Tere Anni

    Pakun, et hakkepuidu turg on teil Eestis kaetud ja müügiga siin abi ei ole vaja. Aga kas eksporti tahaksite rohkem teha?

    Ma ehitan müügitööriistu. Ei, mitte täis AI lahendusi. Mõistlikke lahendusi, kus kulud ja tulud tulevad stabiilselt kokku. Fookus on balti ja skandinaavia riikidel.

    Kas tahaksid 45 sek tutvustavat videot?

    Oscar
    """
  }

  setup do
    user =
      User
      |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
      |> Ash.create!(authorize?: false)

    {:ok, campaign} = Campaign.create_draft("Inherit", actor: user)
    {:ok, campaign} = Campaign.set_icp(campaign, "B2B", "CEO", :b2b, actor: user)
    {:ok, campaign} = Campaign.set_market(campaign, :ee, actor: user)
    {:ok, _sequence} = Sequence.create_default(campaign.id, actor: user)

    # One existing, labeled opener — the only template in the campaign, so the
    # writer's pick is deterministic.
    seeded = seed_opener(campaign, user, 0, @template.subject, @template.body)

    {:ok, _} =
      OutboundEmail.update_template(
        seeded,
        @template.label,
        @template.angle,
        @template.ask,
        @template.offer,
        actor: user,
        authorize?: false
      )

    %{user: user, campaign: campaign}
  end

  @tag timeout: 60_000
  test "the AI-written opener inherits the campaign's template at write time", %{
    user: user,
    campaign: campaign
  } do
    # A fresh contact with no opener yet.
    {:ok, company} =
      Company.upsert_basic(
        %{
          registry_code: "10009999",
          market: :ee,
          name: "Fresh OÜ",
          region: "Tallinn",
          status: :registered
        },
        actor: user,
        authorize?: false
      )

    {:ok, person} =
      Person.create_validated(
        %{company_id: company.id, name: "Mart Tamm", title: "CEO", email: "mart@fresh.ee"},
        actor: user,
        authorize?: false
      )

    {:ok, contact} = CampaignContact.promote(campaign.id, person.id, actor: user)

    assert {:ok, %{emails: emails}} = EmailWriter.run(contact, actor: user)

    opener = Enum.find(emails, &(&1.step_position == 0))
    assert opener, "writer produced no opener"

    assert opener.template_label == @template.label,
           "expected the written opener to inherit #{@template.label}, got #{inspect(opener.template_label)}"

    assert opener.template_angle == @template.angle
    assert opener.template_ask == @template.ask

    # Followups are not templated — the label is an opener concept.
    Enum.each(emails, fn e ->
      if e.step_position != 0, do: refute(e.template_label)
    end)
  end

  defp seed_opener(campaign, user, idx, subject, body) do
    {:ok, company} =
      Company.upsert_basic(
        %{
          registry_code: "1000#{String.pad_leading(to_string(idx), 4, "0")}",
          market: :ee,
          name: "Company #{idx} OÜ",
          region: "Tallinn",
          status: :registered
        },
        actor: user,
        authorize?: false
      )

    {:ok, person} =
      Person.create_validated(
        %{
          company_id: company.id,
          name: "Person #{idx}",
          title: "CEO",
          email: "person#{idx}@example.ee"
        },
        actor: user,
        authorize?: false
      )

    {:ok, contact} = CampaignContact.promote(campaign.id, person.id, actor: user)
    {:ok, thread} = Thread.create_for_contact(contact.id, actor: user)

    {:ok, opener} =
      OutboundEmail
      |> Ash.Changeset.for_create(
        :create_draft,
        %{thread_id: thread.id, step_position: 0, ai_subject: subject, ai_body: body},
        actor: user
      )
      |> Ash.create(actor: user)

    {:ok, opener} = OutboundEmail.update_user_fields(opener, subject, body, actor: user)
    opener
  end
end
