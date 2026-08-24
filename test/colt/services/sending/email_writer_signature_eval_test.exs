defmodule Colt.Services.Sending.EmailWriterSignatureEvalTest do
  @moduledoc """
  Hits the real model (costs money, non-deterministic) — excluded from the
  normal suite via the `:eval` tag set up in test/test_helper.exs. Checks
  whether the writer's prompt reliably closes with the sender's own
  signature, across a few signature "shapes" (name only, name+phone,
  name+phone+link) and across example pools whose OWN sign-off doesn't
  look like the sender's — a bare brand/domain, or no sign-off at all.
  Fixture bodies are adapted from real prod cases where the signature came
  out wrong or missing entirely; names/companies are fictional.

  Run: mix test --only eval test/colt/services/sending/email_writer_signature_eval_test.exs
  """
  use Colt.DataCase, async: false

  @moduletag :eval

  alias Ash.Seed
  alias Colt.Accounts.User

  alias Colt.Resources.{
    Campaign,
    CampaignContact,
    Company,
    EmailAccount,
    OutboundEmail,
    Person,
    Pitch,
    Sequence,
    SequenceStep,
    Thread
  }

  alias Colt.Services.Sending.EmailWriter

  # A clean template: every example is a full opener+followups sequence,
  # consistently signed by the sender who actually wrote it, plus a couple
  # of mid-thread manual replies that qualify as "user-edited" examples but
  # carry NO sign-off at all — the kind of contamination that sneaks into
  # a real example pool once prospects start replying.
  @examples [
    %{
      person: "Peeter Saar",
      company: "Katteid OÜ",
      steps: [
        {0,
         "Tere Peeter\n\nNäen, et aastal 2024 teie käive küll veidi kasvas, aga töötajate arv kahanes korralikult. Kas see tuleneb otseselt turust või oleksite parema müügitööga siiski kasvada saanud?\n\nMa saaksin müügiga aidata. Nimelt ehitan tööriistu. Mitte mingeid AI võlujooke, vaid mõistlikke lahendusi, kus kulud ja tulud tulevad stabiilselt kokku. Fookus on balti ja skandinaavia riikidel. Mu tööriist otsib kontaktid, saadab meilid ja lisateenusena teeb inimene ka kõned otsa.\n\nKas võin sulle saata 45 sek tutvustava lühivideo?\n\nTaavi\n5000 0001\nhttps://liid.ee"},
        {1,
         "Igaks juhuks küsin, kas teil praegu ei ole müügi kasvatamise huvi või on kogemata ajapuudusest vastamata jäänud? Võib ka lihtsalt helistada.\n\nTaavi\n5000 0001\nhttps://liid.ee"},
        {2,
         "Selge, ju siis ei ole hetkel huvi. Jätan rahule. Tulevikuks on aga sul mu number olemas.\n\nTaavi\n5000 0001\nhttps://liid.ee"}
      ]
    },
    %{
      person: "Liina Kask",
      company: "Õigusbüroo Test",
      steps: [
        {0,
         "Tere Liina\n\nNäen, et teete alla kümne inimesega varsti miljoni käivet. Kindlasti tahaksid selle lävendi ületada ja siis veel edasi minna. Mis sul praegu kasvu kõige rohkem takistab? Hea töötaja leidmine või lihtsalt müük? Viimasega saan aidata.\n\nMa ehitan müügitööriistu. Ei, mitte täis AI lahendusi. Mõistlikke lahendusi, kus kulud ja tulud tulevad stabiilselt kokku. Fookus on Balti ja Skandinaavia riikidel. Mu tööriist otsib kontaktid, saadab meilid ja lisateenusena teeb inimene ka kõned otsa.\n\nKas võin sulle saata 45 sek tutvustava lühivideo?\n\nRein Tamm\n5000 0002\nhttps://liid.ee"},
        {1,
         "Igaks juhuks küsin, kas teil praegu ei ole müügi kasvatamise huvi või on kogemata ajapuudusest vastamata jäänud? Võib ka lihtsalt helistada.\n\nRein\n5000 0002\nhttps://liid.ee"},
        {2,
         "Selge, ju siis ei ole hetkel huvi. Jätan rahule. Tulevikuks on aga sul mu number olemas.\n\nRein\n5000 0002\nhttps://liid.ee"}
      ]
    },
    %{
      person: "Anu Mets",
      company: "Joogitehas Test",
      steps: [
        {0,
         "Tere Anu\n\nSaan aru, et olete juba baltikumi ja skandinaavia ära haaranud. Mis turgu te järgmiseks mõtlete üle võtta?\n\nMa ehitan müügitööriistu. Ei, mitte täis AI lahendusi. Mõistlikke lahendusi, kus kulud ja tulud tulevad stabiilselt kokku. Fookus on balti ja skandinaavia riikidel. Mu tööriist otsib kontaktid, saadab meilid ja lisateenusena teeb inimene ka kõned otsa.\n\nJuhul kui teil on üldse plaan edasi laieneda, siis kas võin saata 45 sekundilise tutvustava lühivideo?\n\nRein\n5000 0002\nhttps://liid.ee"},
        {1,
         "Igaks juhuks küsin, kas teil praegu ei ole müügi kasvatamise huvi või on kogemata ajapuudusest vastamata jäänud? Võib ka lihtsalt helistada.\n\nRein\n5000 0002\nhttps://liid.ee"},
        {2,
         "Selge, ju siis ei ole hetkel huvi. Jätan rahule. Tulevikuks on aga sul mu number olemas.\n\nRein\n5000 0002\nhttps://liid.ee"}
      ]
    },
    %{
      person: "Liis Org",
      company: "Pagaritööstus Test",
      steps: [
        {nil, "Selge. Tänud vastamast."}
      ]
    },
    %{
      person: "Andres Kivi",
      company: "Animatsioonistuudio Test",
      steps: [
        {nil, "Selge, tänud vastamast."}
      ]
    },
    # A thread with only manual-reply history — no drafted opener was ever
    # user-edited, so the model only ever sees mid-conversation replies for
    # this contact, never a full opener+signature.
    %{
      person: "Argo Peet",
      company: "Renderdusstuudio Test",
      steps: [
        {nil,
         "Väga vabandan müra pärast. Sattusin hoogu ja käivitasin kampaania enne puhkusele minekut ja ei hoidnud silma peal. Ma saadan teile tutvustava video kui puhkuselt tagasi olen, augustis.\n\nRein / Tarmo\n5000 0002"},
        {nil,
         "Nii, puhkuselt tagasi. Siin on lubatud ülevaade, kuidas Liid müügiga aitab: Liidi ülevaade (5min)\n\nAnna teada, mis segane.\n\nRein\n5000 0002"},
        {nil,
         "Hei. Kes praegu müügiga ei tegele, homme klienti ei saa :) Liidi ülevaade (5min)\n\nMa helistan paari päeva pärast üle ka.\n\nRein\n5000 0002"}
      ]
    }
  ]

  @pitch_summary "Ma ehitan müügitööriistu. Mitte täis AI lahendusi vaid mõistlikke lahendusi, kus kulud ja tulud tulevad stabiilselt kokku. Fookus on balti ja skandinaavia riikidel. Mu tööriist otsib kontaktid, saadab meilid ja lisateenusena teeb inimene ka kõned otsa."

  # A different template whose examples pitch a guest (a well-known
  # performer the sender brings along) and sign off with the BRAND DOMAIN
  # only — no personal name at all. This is the real failure mode: two
  # different real senders both had their name silently replaced by the
  # example's bare domain.
  @domain_examples [
    %{
      person: "Signe Vaher",
      company: "Disainiagentuur Test",
      steps: [
        {0,
         "Hei Signe.\n\nIlmselt tead, kes Karl Metsis on. Teda näeb vahel telesaates, aga tegelt on suur osa meie lemmik lugusid tema produtseeritud.\n\nKuidas teile meeldiks Karliga koos muusikat teha? Karl tuleb ja õpetab kogu tiimile millest koosneb üks õige hitt ja kuidas see ise AI-ga valmis teha. Siis kolleegid saavad võistelda oma loominguga. See on lihtne ja lõbus õhtu Eesti muusika legendiga.\n\nKuidas tundub, kas tahaksid Karliga lähemalt rääkida?\n\nfirmapidu.ee"}
      ]
    },
    %{
      person: "Priit Mäe",
      company: "IT Nõustajad Test",
      steps: [
        {0,
         "Hei Priit.\n\nIlmselt tead, kes Karl Metsis on. Teda näeb vahel telesaates, aga tegelt on suur osa meie lemmik lugusid tema produtseeritud.\n\nKuidas teile meeldiks Karliga koos muusikat teha? Karl tuleb ja õpetab kogu tiimile millest koosneb üks õige hitt ja kuidas see ise AI-ga valmis teha. Siis kolleegid saavad võistelda oma loominguga. See on lihtne ja lõbus õhtu Eesti muusika legendiga.\n\nKuidas tundub, kas tahaksid Karliga lähemalt rääkida?\n\nfirmapidu.ee"}
      ]
    }
  ]

  @domain_pitch_summary "Korraldame firmadele muusikaüritusi, kus tuntud Eesti muusik õpetab tiimile loomingut ja produtseerimist."

  # Signature "shapes" a real user might type into an email account —
  # sometimes just a name, sometimes name+number, etc.
  @signature_variants [
    {"name_only", "Peep Ojasaar"},
    {"name_plus_phone", "Peep Ojasaar\n5000 0009"},
    {"name_phone_link", "Peep Ojasaar\n5000 0009\nliid.ee"}
  ]

  test "does the AI-drafted opener carry the sender's signature, across signature shapes?" do
    %{sequence: sequence} = graph_with_examples(@examples, @pitch_summary)

    results =
      Enum.map(@signature_variants, fn {label, sig} ->
        contact = target_contact(sequence, sig, "Tanel Saks", "Ökoenergia")

        {:ok, %{emails: emails}} = EmailWriter.run(contact, sequence_id: sequence.id, actor: nil)

        opener = Enum.find(emails, &(&1.step_position == 0))
        body = opener.ai_body || ""
        signed? = String.contains?(body, "Peep")

        IO.puts("\n=== #{label} (signature: #{inspect(sig)}) ===")
        IO.puts(body)
        IO.puts("--- signed with sender name? #{signed?} ---")

        {label, signed?, body}
      end)

    signed_count = Enum.count(results, fn {_, signed?, _} -> signed? end)
    IO.puts("\n#{signed_count}/#{length(results)} openers carried the sender's signature")

    assert signed_count == length(results),
           "expected every opener to carry the sender's signature, got #{signed_count}/#{length(results)}"
  end

  test "does the opener carry the sender's own signature when the examples sign off with a bare brand domain?" do
    %{sequence: sequence} = graph_with_examples(@domain_examples, @domain_pitch_summary)

    results =
      Enum.map(
        [
          {"taavi", "Taavi Org\n5000 0003\nliid.ee"},
          {"marten", "Marten Kuusk\n5000 0004\nliid.ee"}
        ],
        fn {label, sig} ->
          contact = target_contact(sequence, sig, "Liisa Rand", "Disainistuudio")

          {:ok, %{emails: emails}} =
            EmailWriter.run(contact, sequence_id: sequence.id, actor: nil)

          opener = Enum.find(emails, &(&1.step_position == 0))
          body = opener.ai_body || ""
          sender_name = sig |> String.split("\n") |> List.first()
          signed? = String.contains?(body, sender_name)

          IO.puts("\n=== #{label} (signature: #{inspect(sig)}) ===")
          IO.puts(body)
          IO.puts("--- signed with sender name (#{sender_name})? #{signed?} ---")

          {label, signed?, body}
        end
      )

    signed_count = Enum.count(results, fn {_, signed?, _} -> signed? end)
    IO.puts("\n#{signed_count}/#{length(results)} openers carried the sender's own signature")

    assert signed_count == length(results),
           "expected every opener to carry the sender's own signature (not the example's bare domain), got #{signed_count}/#{length(results)}"
  end

  defp graph_with_examples(examples, pitch_summary) do
    n = System.unique_integer([:positive])
    user = Seed.seed!(User, %{email: "owner-#{n}@liid.app"})
    campaign = Seed.seed!(Campaign, %{name: "Camp #{n}", owner_id: user.id})

    sequence =
      Seed.seed!(Sequence, %{campaign_id: campaign.id, name: "template-#{n}", language: "et"})

    Enum.each(
      [{0, :email, 0}, {1, :email, 2}, {2, :email, 2}, {3, :terminal, 7}],
      fn {position, kind, delay_days} ->
        Seed.seed!(SequenceStep, %{
          sequence_id: sequence.id,
          position: position,
          kind: kind,
          delay_days: delay_days
        })
      end
    )

    example_inbox =
      Seed.seed!(EmailAccount, %{
        user_id: user.id,
        provider: :imap,
        address: "examples-#{n}@liid.app",
        tz: "Europe/Tallinn",
        daily_quota: 50,
        status: :healthy
      })

    Enum.each(examples, fn ex ->
      company =
        Seed.seed!(Company, %{
          name: ex.company,
          registry_code: "EE#{System.unique_integer([:positive])}",
          market: :ee
        })

      person =
        Seed.seed!(Person, %{
          name: ex.person,
          email:
            "#{String.downcase(String.replace(ex.person, " ", "."))}-#{System.unique_integer([:positive])}@target.ee",
          company_id: company.id
        })

      contact =
        Seed.seed!(CampaignContact, %{
          campaign_id: campaign.id,
          person_id: person.id,
          status: :no_reply,
          sequence_id: sequence.id,
          assigned_email_account_id: example_inbox.id
        })

      thread = Seed.seed!(Thread, %{campaign_contact_id: contact.id})

      Enum.each(ex.steps, fn {position, body} ->
        Seed.seed!(OutboundEmail, %{
          thread_id: thread.id,
          step_position: position,
          status: :sent,
          is_manual_reply: is_nil(position),
          user_subject:
            cond do
              position == 0 -> "example subject"
              is_nil(position) -> "re: example subject"
              true -> nil
            end,
          user_body: body,
          email_account_id: example_inbox.id
        })
      end)
    end)

    Seed.seed!(Pitch, %{
      campaign_id: campaign.id,
      domain: "liid.ee",
      user_summary: pitch_summary
    })

    %{sequence: sequence}
  end

  defp target_contact(sequence, signature, person_name, company_name) do
    n = System.unique_integer([:positive])
    user = Seed.seed!(User, %{email: "sender-#{n}@liid.app"})

    company =
      Seed.seed!(Company, %{
        name: "#{company_name} #{n}",
        registry_code: "EE#{n}",
        market: :ee,
        region: "Harjumaa",
        status: :registered,
        employees_latest: 5,
        revenue_latest: Decimal.new("612000"),
        revenue_growth_bucket: :stagnant,
        ai_summary: "#{company_name} tegutseb Eestis, viie töötajaga."
      })

    person =
      Seed.seed!(Person, %{
        name: person_name,
        email: "#{String.downcase(String.replace(person_name, " ", "."))}-#{n}@target.ee",
        company_id: company.id
      })

    inbox =
      Seed.seed!(EmailAccount, %{
        user_id: user.id,
        provider: :imap,
        address: "sender-#{n}@liid.app",
        display_name: signature,
        tz: "Europe/Tallinn",
        daily_quota: 50,
        status: :healthy
      })

    contact =
      Seed.seed!(CampaignContact, %{
        campaign_id: sequence.campaign_id,
        person_id: person.id,
        status: :sending,
        sequence_id: sequence.id,
        assigned_email_account_id: inbox.id
      })

    Seed.seed!(Thread, %{campaign_contact_id: contact.id})

    contact
  end
end
