defmodule Colt.Services.Sending.LabelTemplateTest do
  @moduledoc """
  Eval for the template categorizer (§6.2). Seeds a campaign whose three
  existing templates are real openers from prod (export-expansion-demo,
  revenue-decline-demo, revenue-milestone-demo), then classifies a fourth
  opener that takes a genuinely different approach — the contrarian "why AI
  sales tools don't work" pitch, which has no market/revenue angle at all.

  The categorizer must mint a NEW template for it, not collapse it into one of
  the existing three. In prod it wrongly labeled every copy of this email
  `export-expansion-demo`; this test pins that behavior.

  Tagged `:eval` — it calls the live model and is excluded by default. Run it
  with `mix test --only eval`. When categorization regresses, drop the new
  problem email into `@different_opener` and rerun.
  """
  use Colt.DataCase, async: false

  @moduletag :eval

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, CampaignContact, Company, OutboundEmail, Person, Thread}
  alias Colt.Services.Sending.LabelTemplate

  # ── The existing template(s), as real prod openers ──────────────────────
  #
  # We seed ONLY export-expansion-demo, faithfully reproducing the moment the
  # prod backfill failed: ordered oldest-first, the first six openers were all
  # export-expansion variants, so when the "why AI tools fail" openers (records
  # 7-13) were classified, export-expansion-demo was the *only* template that
  # existed. The revenue templates didn't appear until much later. Seeding all
  # three made the call too easy — the bug only bites under this single-template
  # context, where the prompt's reuse bias has nothing to contrast against.

  @export_expansion %{
    label: "export-expansion-demo",
    angle: "Domestic market is covered; the export potential is untapped.",
    ask: "Want to sell more into Finland/Sweden? 45s intro video?",
    offer: "Sensible sales tooling (not full AI) that finds contacts and sends mail.",
    subject: "Hakkepuidu turg Eestis ja naabruskonnas",
    body: """
    Tere Anni

    Pakun, et hakkepuidu turg on teil Eestis kaetud ja müügiga siin abi ei ole vaja. Aga kas eksporti tahaksite rohkem teha?

    Ma ehitan müügitööriistu. Ei, mitte täis AI lahendusi. Mõistlikke lahendusi, kus kulud ja tulud tulevad stabiilselt kokku. Fookus on balti ja skandinaavia riikidel. Mu tööriist otsib kontaktid, saadab meilid ja lisateenusena teeb inimene ka kõned otsa.

    Kas tahaksid 45 sek tutvustavat videot?

    Oscar
    """
  }

  @existing_templates [@export_expansion]
  @existing_labels Enum.map(@existing_templates, & &1.label)

  # ── The opener that must NOT collapse into the above ─────────────────────

  @different_opener %{
    subject: "Miks AI müügitööriistad ei tööta?",
    body: """
    AI müügitööriistad ei tööta, sest

    1. AI on liiga kallis, et juhatada tervet müügiprotsessi ja teha otsuseid. Pole haruldane maksta tuhandeid ja saada null tulemust.
    2. AI teeb liiga palju vigu. Ja need on üsna kallid vead. Nii kulude, kaotatud kliendi kui ka maine pärast.
    3. Inimesed on nüüdseks harjunud nägema AI kirjutatud tekste. Ja kõik teavad, et AI iseseisvalt lihtsalt ei ole väga hea.

    Tegelikult on lahendus lihtne. Ma ehitan müügitööriistu, kus AI teeb ainult seda, milles ta on hea, ja inimene teeb ülejäänu. Fookus on Balti ja Skandinaavia riikidel.

    Kas tahaksid 45 sek tutvustavat videot?

    Oscar
    """
  }

  # A genuine reword of export-expansion (different industry, same premise and
  # ask) — must still collapse into the existing label, not spawn its own.
  @reword_opener %{
    subject: "tööstusplastide müük soome ja rootsi",
    body: """
    Tere Kristo

    Pakun, et tööstuslike plastide ja kummimaterjalide müük käib Eestis hästi ja siin abi ei ole vaja. Aga kas Soome või Rootsi turule tahaksite rohkem müüa?

    Ma ehitan müügitööriistu. Ei, mitte täis AI lahendusi. Mõistlikke lahendusi, kus kulud ja tulud tulevad stabiilselt kokku. Fookus on balti ja skandinaavia riikidel. Mu tööriist otsib kontaktid, saadab meilid ja lisateenusena teeb inimene ka kõned otsa.

    Kas tahaksid 45 sek tutvustavat videot?

    Oscar
    """
  }

  setup do
    user =
      User
      |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
      |> Ash.create!(authorize?: false)

    {:ok, campaign} = Campaign.create_draft("Eval", actor: user)
    {:ok, campaign} = Campaign.set_icp(campaign, "B2B", "CEO", :b2b, actor: user)
    {:ok, campaign} = Campaign.set_market(campaign, :ee, actor: user)

    # Seed the three existing templates as labeled openers in this campaign.
    @existing_templates
    |> Enum.with_index()
    |> Enum.each(fn {t, idx} ->
      opener = seed_opener(campaign, user, idx, t.subject, t.body)

      {:ok, _} =
        OutboundEmail.update_template(opener, t.label, t.angle, t.ask, t.offer,
          actor: user,
          authorize?: false
        )
    end)

    %{user: user, campaign: campaign}
  end

  @tag timeout: 60_000
  test "classifies a different-approach opener as its own template, not an existing one", %{
    user: user,
    campaign: campaign
  } do
    opener = seed_opener(campaign, user, 99, @different_opener.subject, @different_opener.body)

    # Reload with the associations LabelTemplate needs to scope per-campaign,
    # mirroring the backfill path (no actor → authorize? false).
    loaded = OutboundEmail.get!(opener.id, load: [thread: [:campaign_contact]], authorize?: false)

    assert {:ok, labeled} = LabelTemplate.run(loaded)

    refute labeled.template_label in @existing_labels,
           """
           Expected the "why AI sales tools don't work" opener to get its own \
           template, but the categorizer collapsed it into an existing one: \
           #{labeled.template_label}.
           angle: #{labeled.template_angle}
           ask:   #{labeled.template_ask}
           """
  end

  @tag timeout: 60_000
  test "reuses an existing template for a reworded opener (same approach, new industry)", %{
    user: user,
    campaign: campaign
  } do
    opener = seed_opener(campaign, user, 98, @reword_opener.subject, @reword_opener.body)
    loaded = OutboundEmail.get!(opener.id, load: [thread: [:campaign_contact]], authorize?: false)

    assert {:ok, labeled} = LabelTemplate.run(loaded)

    assert labeled.template_label == "export-expansion-demo",
           """
           Expected the reworded export opener to reuse export-expansion-demo, \
           but the categorizer split it into: #{labeled.template_label}. \
           The fix must not over-correct into a label per industry.
           """
  end

  # Creates a company → person → contact → thread → step-0 opener, marks it
  # user-edited (every prod opener in this campaign is), and returns the opener.
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
