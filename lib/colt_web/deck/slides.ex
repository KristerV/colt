defmodule ColtWeb.Deck.Slides do
  @moduledoc """
  The demo deck: slides as code, not as data.

  There is deliberately no slide editor. A slide is a HEEx function here, which
  means full HTML/CSS, real product numbers pulled at render time, and a git
  diff when the pitch changes.

  Copy is Estonian, hardcoded rather than run through gettext: the deck is a
  single-market pitch and its prose is dense enough that translating it is a
  rewrite, not a substitution.

  Three things are keyed off `slide_key`:

  - `order/1` — which slides each A/B variant plays, and in what sequence.
    `features` is the product tour; `solving_emails` pitches the same product
    through deliverability. Adding a variant is a new clause, not a schema
    change.
  - narration — `Colt.Deck.Manifest` points at recorded clips by `slide_key`,
    so slides shared between variants share one recording. `cta` closes both
    decks and is recorded once.
  - `script/1` — what to say over the slide. Shown in `/admin/deck` as a
    teleprompter, never to the prospect.

  Every slide renders into a 16:9 stage that is `container-type: size`, so all
  type is sized in `cqw` (percent of stage width) and the layout is identical at
  any viewport — see the `deck-*` styles below.

  The first slide of each variant is its cover: it carries the Play button and
  the deck sits on it until clicked. That button *must* keep its
  `data-deck-start` attribute — `DeckPlayer` starts the video inside that
  click's own handler, and that is the only thing that buys audio permission
  for every clip after it.
  """
  use ColtWeb, :html

  @features [
    :f_cover,
    :f_intro,
    :f_part_contacts,
    :f_alternatives,
    :f_process,
    :f_filter,
    :f_validate,
    :f_contacts,
    :f_part_sending,
    :f_sending,
    :f_writing,
    :f_volume,
    :f_reply,
    :f_summary,
    :cta
  ]

  @solving_emails [
    :s_cover,
    :s_intro,
    :s_risk,
    :s_rules,
    :s_targeting,
    :s_voice,
    :s_volume,
    :s_summary,
    :cta
  ]

  @doc "Every A/B variant the deck is built for, in presentation order."
  def variants, do: ["features", "solving_emails"]

  @doc """
  Slide order for an ab_funnel variant. Unknown/absent variant gets `features`.

  Dashes are accepted so `/demo/solving-emails` reads naturally in a link even
  though the cookie stores the atom's underscored form.
  """
  def order(variant) when is_binary(variant) do
    case String.replace(variant, "-", "_") do
      "solving_emails" -> @solving_emails
      _ -> @features
    end
  end

  def order(_), do: @features

  @doc "Every slide that exists, for the studio's recording list."
  def all_keys, do: Enum.uniq(@features ++ @solving_emails)

  @doc "True for slides that open a deck — these hold until Play is clicked."
  def cover?(key), do: key in [:f_cover, :s_cover]

  def title(:f_cover), do: "Avaslaid"
  def title(:f_intro), do: "Kaks asja: kontaktid ja meilid"
  def title(:f_part_contacts), do: "Vahe: kontaktid"
  def title(:f_alternatives), do: "Kust sa täna kontakte saad"
  def title(:f_process), do: "Kogu kontaktide teekond"
  def title(:f_filter), do: "Registriinfo ja filtrid"
  def title(:f_validate), do: "AI loeb kodulehed läbi"
  def title(:f_contacts), do: "Õige inimene firmas"
  def title(:f_part_sending), do: "Vahe: e-mailide saatmine"
  def title(:f_sending), do: "Meilide lehter"
  def title(:f_writing), do: "AI õpib sinu kirjast"
  def title(:f_volume), do: "Mitu domeeni ja aadressi"
  def title(:f_reply), do: "Vastus tuli"
  def title(:f_summary), do: "Kokkuvõte ja Krister"

  def title(:s_cover), do: "Avaslaid"
  def title(:s_intro), do: "10 000 kirja ei tööta enam"
  def title(:s_risk), do: "Risk on su domeen"
  def title(:s_rules), do: "Kolm reeglit"
  def title(:s_targeting), do: "Reegel 1: õiged firmad"
  def title(:s_voice), do: "Reegel 2: sinu käekiri"
  def title(:s_volume), do: "Reegel 3: 20 kirja päevas"
  def title(:s_summary), do: "Kokkuvõte"

  def title(:cta), do: "Mis edasi? (mõlemas kavas)"

  ## ---------- narration scripts ----------

  @doc """
  What to say over a slide. Rendered in `/admin/deck` as a teleprompter and
  nowhere else — the prospect never sees this text.
  """
  def script(:f_cover),
    do: """
    (Avaslaid, ei ole vaja salvestada. Vaataja vajutab siin Play.)
    """

  def script(:f_intro),
    do: """
    Liid aitab sul külmaks müügiks kontakte leida ja siis meilid saata nagu
    proff, vähese vaevaga.

    Kui sa kirjeldad ära mida sa otsid, siis peaksid vastu saama juba
    huvitatud kontakte.
    """

  def script(:f_part_contacts),
    do: """
    Alustame esimesest poolest: kust need kontaktid üldse tulevad.
    """

  def script(:f_alternatives),
    do: """
    Kui sa täna omale värskeid kontakte tahad, siis võid sa neid käsitsi
    otsida, osta neid Äripäevalt või siis rahvusvahelisest teenusest nagu
    Apollo.

    Käsitsi saad värske info, aga see võtab aega. Äripäev annab sulle ainult
    eesti kontaktid. Apollo annab lihtsalt aegunud infot. Kui sa tahad
    müügitoru, mis müüb värske info põhjalt Eestis ja välismaal, siis Liid on
    ainus valik.
    """

  def script(:f_process),
    do: """
    Enne kui detailidesse läheme, siin on kogu teekond ühel pildil.

    Liid võtab Eesti, Läti, Leedu, Soome, Rootsi ja Norra ametlikud
    äriregistrid. Sealt filtreerid välja esmase valimi, Liid leiab igale
    firmale kodulehe, AI loeb kodulehe läbi ja kontrollib, kas see firma on
    päriselt sinu sihtgrupp, ja alles siis korjab kodulehelt kontaktid.

    Nüüd vaatame iga sammu eraldi.
    """

  def script(:f_filter),
    do: """
    Liid võtab erinevate riikide ametliku info, mille põhjalt sa saad
    filtreerida omale esmase valimi. Filtrid on tegevusala, töötajate arv ja
    käive.
    """

  def script(:f_validate),
    do: """
    Siis Liid läheb ja käib nende firmade kodukad läbi ja esiteks kontrollib,
    et see firma on reaalselt sinu sihtgrupp.

    See on oluline selleks, et sa ei saadaks firmadele meili, kelle kodukalt on
    juba näha, et nad niikuinii ei ostaks sinu teenust. Lõpuks tahad sa, et
    saadad ainult õigetele firmadele, et kulud oleks väiksed ja et su meilid ei
    läheks spämmi.
    """

  def script(:f_contacts),
    do: """
    Kui firma on valideeritud kui hea kontakt, siis ta võtab kodukalt kontaktid
    vastavalt su kirjeldusele, kellega rääkida tahad.

    Juhul kui soovid omaniku kontakti, siis vaatame üle, kas registris olev on
    inimese oma või üldkontakt, ja kontrollime ka, kas see üldse eksisteerib.
    """

  def script(:f_part_sending),
    do: """
    Kontaktid on olemas. Nüüd teine pool: kuidas neile kirjad välja lähevad.
    """

  def script(:f_sending),
    do: """
    Kontakt siis läheb edasi meilide lehtrisse. Liid saadab esimese kirja ja ka
    followupid iga mõne päeva tagant. Kui keegi on puhkusel, oskab süsteem
    sellega arvestada ja lükkab järgmise kirja edasi, kuniks ta on puhkuselt
    tagasi.

    Kui sa tahad igale firmale üle helistada, siis paneb Liid kontaktid "kõneks
    valmis" kausta, kus saad kõne ära teha. Kui sa ise kõnesid teha ei taha, aga
    tead, et tegelt on vaja, saad selle meilt sisse osta.
    """

  def script(:f_writing),
    do: """
    AI ei ole hea kirja kirjutaja. Aga ta on hea automatiseerija. Seega sina
    kirjutad esimesed meilid ja AI õpib sinu kirja pealt, mida edaspidi saata.

    Kui tunned end kindlalt, et AI kirjutab õigesti ja arvestab muutuvate
    detailidega, siis saad kampaania automaatseks teha.
    """

  def script(:f_volume),
    do: """
    Üks meiliaadress ei tohiks saata rohkem kui kakskümmend kirja päevas, muidu
    hakkab Google sind spämmiks pidama. Ja ühel domeenil võiks olla kuni kolm
    saatvat aadressi.

    Seega kui sa tahad päevas sada kaheksakümmend kirja saata, on sul vaja kolme
    domeeni ja igal domeenil kolme aadressi. Liid laseb sul neid kõiki ühendada
    ja jagab kirjad ise nende vahel ära, nii et ükski aadress oma päevalimiiti
    ei ületa. Sina ei pea seda arvutama.
    """

  def script(:f_reply),
    do: """
    Kui potentsiaalne klient vastab, siis saad temaga Liidis edasi suhelda või
    siis eksportida teise süsteemi nagu Pipedrive.
    """

  def script(:f_summary),
    do: """
    Kokkuvõttes teeb Liid kaks asja. Leiab üles need kontaktid, kes päriselt
    sinu sihtgruppi sobivad, mitte lihtsalt suure nimekirja. Ja saadab neile
    kirjad automaatselt, aga maitsekalt, sinu käekirjaga ja mõistlikus tempos.

    Ja kui need kaks asja on korras, siis tuleb kolmas ise järele: kirjad ei
    lähe spämmi, vaid jõuavad päriselt postkasti. Nii Eestis kui ka Baltikumis
    ja Skandinaavias.

    Mina olen Krister, ehitasin Liidi, sest mul endal oli vaja kliente juurde
    leida. Kui töötava lahenduse ehitasin, siis tahtsin seda teistele ka
    pakkuda.

    Kontaktide ja külma meili maailm areneb pidevalt ja kiiresti. Kui sul just
    ei ole endal aega pidevalt silma peal hoida, kuidas Google ja teised oma
    spämmi filtreid muudavad, siis parem kasuta tööriista, mis lihtsalt töötab.
    """

  def script(:s_cover),
    do: """
    (Avaslaid, ei ole vaja salvestada. Vaataja vajutab siin Play.)
    """

  def script(:s_intro),
    do: """
    Liid on müügitööriist, mis leiab sulle värsked kontaktid, kes on täpselt
    sinu sihtgrupis. See on terviklahendus, et saaksid ideest huvilisteni jõuda
    ühes kohas. Ja seda nii, et su domeen ei kannata ja ei satu spämmi.

    Kuidas siis täna saata meile nii, et need ei läheks spämmi? Enam ei saa
    lihtsalt 10 000 meili välja saata ja loota, et keegi sulle vastab. Google
    kasutab ju ikkagi tänapäevast AI-d, et spämmi tuvastada. Vanad harjumused
    hävitavad su domeeni maine ja kogu su firma meilid võivad järsku spämmi
    sattuda.
    """

  def script(:s_risk),
    do: """
    Risk on päris korralik. Kui sa saadad liiga palju kirju liiga kiiresti
    valedele kontaktidele, võid paari tunniga oma kogu firma domeeni
    prügikasti visata. Siis ei leia sind enam Googlest ega ei soovita AI
    agendid. Isegi vestlused klientidega lähevad punaseks.

    Aga domeen on ainult pool asja. Domeeni saab lõpuks parandada, mainet mitte.
    Eestis ja Baltikumis on sinu sihtgrupis piiratud arv firmasid. Kui sa saadad
    neile kõigile korraga ühe halva kirja, siis oled selle turu ära põletanud,
    ja see on ainus turg mis sul on. Järgmine kord, kui sul on päriselt hea
    pakkumine, mäletatakse sind juba spämmijana ja kirja ei avata.

    Ära riski kummagagi. Kui ei viitsi end kurssi viia, kuidas tänapäeval asju
    tehakse, siis kasuta lihtsalt Liidi.
    """

  def script(:s_rules),
    do: """
    Kõik taandub sellele, et kui su kirjadele vastatakse, siis järelikult
    saadad häid meile. Kolm kõige tähtsamat reeglit on: saada ainult neile
    firmadele, kes päriselt võiks sinust huvitatud olla, mitte kõigile keda
    kätte saad; saada kiri, mille oled ise kirjutanud; ja kasuta tänapäevaseid
    meili saatmise taktikaid.

    Kohe räägin neist täpsemalt.
    """

  def script(:s_targeting),
    do: """
    Kui sa oled inimene (see Google'ile meeldib), siis su maht on väike ja sa
    oled iga kontakti firma kodukalt üles leidnud ja kontrollinud, et see firma
    võiks su toodet või teenust üldse osta.

    Liid käib ka kodukalt kontakte otsimas, seega tead, et nad on avatud
    koostööle. Aga lisaks kontrollib Liidi AI, et kodukas vastab täpselt sinu
    sihtgrupile. Ettevõtte tegevusala filter on meil ka olemas, aga see on vaid
    esimene samm. Sina kirjeldad, mida müüd ja kes on ideaalne klient, Liid
    leiab just need firmad üles.

    See tähendab, et su meil ei satu postkasti firmale, kes nii ehk naa ei
    oleks sinult ostnud ja kelle kodukalt oleks selle välja lugenud. See on üks
    tähtsamaid samme, et liiga palju meile ei lähe välja.
    """

  def script(:s_voice),
    do: """
    AI ei ole väga hea kirja kirjutama. Aga kõigile sama stampasja saata ka ei
    tööta. Seega on vaja, et AI kirjutaks nii, nagu sina kirjutad.

    Liid laseb sul esimese kirja ise kirjutada ja siis õpib sellest. Iga
    parandus, mida sa teed, jätab ta meelde ja täiendab oma oskusi. See
    tähendab, et kiri on sinu käekirjaga, aga arvestab erinevate firmade
    eripäradega.

    Muide, täna teavad kõik, et AI kirjutab kirju, ja mingit
    ülepersonaliseeritud kirja pole mõtet saata, lugeja arvab, et on AI spämm.
    Aga kui kirjutad lihtsalt hea pakkumise, mis vastab selle firma vajadustele,
    siis see töötab väga hästi.
    """

  def script(:s_volume),
    do: """
    Meilide saatmisel on kõige tähtsam reegel, et üks meiliaadress ei saadaks
    rohkem kui 20 e-maili päevas. Ja ühel domeenil võib olla kuni kolm
    aadressi, millelt saata. Kui sa tahad 100 meili päevas saata, siis on sul
    vaja kahte domeeni ja mõlemal kolme e-maili aadressi.

    Liid laseb sul ühendada kasvõi kümneid meiliaadresse, millelt saata. Ja me
    vaatame ise, et ühes päevas liiga palju meile välja ei läheks.
    """

  def script(:s_summary),
    do: """
    Ehk siis Liid otsib sulle värsked kontaktid, kes sobivad täpselt sinu
    teenusele või tootele. Ja siis saadab meilid välja nii, et nad ei lähe
    spämmi, kasutades tänapäevaseid taktikaid.

    Nüüd edasi me võime teha kõne või võid katsetada, kuidas süsteem töötab,
    iseseisvalt. Kuidas soovid jätkata?
    """

  def script(:cta),
    do: """
    Mis edasi soovid teha?
    """

  ## ---------- shared stage styles ----------

  @doc """
  The `d-*` / `deck-*` stylesheet shared by the player and the studio.

  Kept as a plain stylesheet rather than utility classes because every size in
  it is in `cqw`, which only means anything inside the `container-type: size`
  stage — see `.deck-stage`.
  """
  def styles(assigns) do
    ~H"""
    <style>
      /* The stage is a fixed 16:9 box that is its own size container, so every
         slide measurement below is in cqw (% of stage width) and the deck looks
         identical on a laptop and on a boardroom screen. */
      .deck-stage {
        width: 100%;
        aspect-ratio: 16 / 9;
        container-type: size;
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 11px;
        box-shadow: var(--shadow-card);
        position: relative;
        overflow: hidden;
      }

      /* Full-screen playback: the stage takes the whole viewport, letterboxed
         to 16:9 so slide layout (all cqw) is identical to the studio preview. */
      .deck-fullscreen .deck-stage {
        width: min(100vw, calc(100vh * 16 / 9));
        border: 0;
        border-radius: 0;
        box-shadow: none;
      }

      /* Extra bottom padding is the face bubble's safe area: content is
         vertically centred inside this box, so the padding lifts it clear of
         the corner the talking head occupies. */
      .d-pad { padding: 4.2cqw 5cqw 9.5cqw; }
      .d-h1 { font-size: 5.4cqw; line-height: 1.04; font-weight: 700; letter-spacing: -0.03em; }
      /* Every slide heading is centred. A left-aligned heading over content
         that is itself centred (a funnel, a fork, a sequence) reads as two
         competing layouts; centring the heading everywhere is what keeps the
         deck feeling like one system. Nothing else uses d-h2. */
      .d-h2 {
        font-size: 3.9cqw; line-height: 1.08; font-weight: 700;
        letter-spacing: -0.025em; text-align: center;
      }
      .d-h3 { font-size: 2.1cqw; line-height: 1.15; letter-spacing: -0.02em; }
      .d-h4 { font-size: 1.75cqw; line-height: 1.2; letter-spacing: -0.015em; }
      .d-lead { font-size: 1.9cqw; line-height: 1.45; font-weight: 450; }
      .d-body { font-size: 1.35cqw; line-height: 1.4; font-weight: 450; }
      .d-fine { font-size: 1.02cqw; line-height: 1.35; }
      .d-kicker {
        font-size: 1.02cqw; font-weight: 600;
        text-transform: uppercase; letter-spacing: 0.09em;
      }
      .d-num {
        font-size: 2.9cqw; font-weight: 700; letter-spacing: -0.02em;
        font-variant-numeric: tabular-nums; line-height: 1.15;
      }
      .d-num-sm {
        font-size: 1.9cqw; font-weight: 700; letter-spacing: -0.02em;
        font-variant-numeric: tabular-nums; line-height: 1.2;
      }

      .d-card {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 11px;
        box-shadow: var(--shadow);
      }
      .d-cardhead {
        padding: 0.7cqw 1.5cqw;
        border-bottom: 1px solid var(--border);
        background: var(--bgSoft);
        color: var(--inkFaint);
        font-size: 0.95cqw; font-weight: 600;
        text-transform: uppercase; letter-spacing: 0.05em;
      }
      .d-chip {
        display: inline-flex; align-items: center; gap: 0.5cqw;
        border-radius: 999px; padding: 0.4cqw 0.9cqw;
        font-size: 1cqw; font-weight: 600;
      }
      .d-dot { width: 0.7cqw; height: 0.7cqw; border-radius: 999px; display: inline-block; }
      .d-inbox {
        background: var(--bgSoft); border: 1px solid var(--border);
        border-radius: 0.45cqw; padding: 0.45cqw 0.9cqw;
        font-size: 1.1cqw; color: var(--inkSoft); white-space: nowrap;
      }
      .d-step-no {
        display: grid; place-items: center;
        width: 2cqw; height: 2cqw; border-radius: 0.6cqw;
        background: var(--bgSoft); color: var(--inkFaint);
        font-size: 0.95cqw; font-weight: 700;
      }
      /* Negatives are meant to be seen. A greyed-out ✕ reads as "disabled"
         from the back of a room; red reads as "this is the bad one". */
      .d-x {
        display: grid; place-items: center;
        width: 1.8cqw; height: 1.8cqw; border-radius: 0.5cqw;
        background: var(--redSoft); color: var(--red);
        font-size: 1cqw; font-weight: 700; flex-shrink: 0;
      }
      .d-avatar {
        display: grid; place-items: center;
        width: 3.2cqw; height: 3.2cqw; border-radius: 0.9cqw;
        background: var(--accentSoft); color: var(--accent);
        font-size: 1.2cqw; font-weight: 700; flex-shrink: 0;
      }
      .d-btn {
        display: inline-flex; align-items: center; justify-content: center;
        background: var(--accent); color: #fff;
        border-radius: 0.7cqw; padding: 1cqw 1.8cqw;
        font-size: 1.4cqw; font-weight: 600;
        box-shadow: var(--shadow); cursor: pointer;
      }
      /* the talking head */
      .deck-bubble {
        position: absolute; right: 2cqw; bottom: 2cqw;
        width: 10.5cqw; height: 10.5cqw; border-radius: 999px;
        object-fit: cover; background: #efeeec;
        border: 0.35cqw solid #fff;
        box-shadow: 0 4px 18px rgba(35,32,28,.18);
        z-index: 3;
      }
      .deck-bubble[hidden] { display: none; }
    </style>
    """
  end

  ## ---------- render ----------

  attr :key, :atom, required: true
  attr :registry_total, :integer, default: 0
  attr :countries, :list, default: []
  attr :slide_count, :integer, default: 0
  attr :minutes, :integer, default: 4

  def slide(assigns) do
    case assigns.key do
      :f_cover -> f_cover(assigns)
      :f_intro -> f_intro(assigns)
      :f_part_contacts -> f_part_contacts(assigns)
      :f_alternatives -> f_alternatives(assigns)
      :f_process -> f_process(assigns)
      :f_filter -> f_filter(assigns)
      :f_validate -> f_validate(assigns)
      :f_contacts -> f_contacts(assigns)
      :f_part_sending -> f_part_sending(assigns)
      :f_sending -> f_sending(assigns)
      :f_writing -> f_writing(assigns)
      :f_volume -> f_volume(assigns)
      :f_reply -> f_reply(assigns)
      :f_summary -> f_summary(assigns)
      :s_cover -> s_cover(assigns)
      :s_intro -> s_intro(assigns)
      :s_risk -> s_risk(assigns)
      :s_rules -> s_rules(assigns)
      :s_targeting -> s_targeting(assigns)
      :s_voice -> s_voice(assigns)
      :s_volume -> s_volume(assigns)
      :s_summary -> s_summary(assigns)
      :cta -> cta(assigns)
    end
  end

  ## ---------- features · cover ----------

  defp f_cover(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full text-center">
      <div class="d-kicker text-accent">Liid</div>
      <h1 class="d-h1 mt-[1.6cqw] max-w-[72cqw] mx-auto">
        Külmaks müügiks värsked kontaktid.
      </h1>

      <div class="mt-[3.4cqw]">
        <button type="button" data-deck-start phx-click="start" class="d-btn mx-auto">
          ▶ Alusta
        </button>
      </div>

      <div class="d-fine text-inkFaint mt-[1.6cqw]">
        {@slide_count} slaidi · umbes {@minutes} min
      </div>
    </div>
    """
  end

  ## ---------- features · what it does ----------

  defp f_intro(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">Kaks asja, ühes kohas.</h2>

      <div class="grid grid-cols-2 gap-[2cqw] mt-[4cqw]">
        <div class="d-card px-[2.4cqw] py-[3cqw] text-center">
          <div class="d-h3 font-bold">Kontaktide leidmine</div>
        </div>

        <div class="d-card px-[2.4cqw] py-[3cqw] text-center">
          <div class="d-h3 font-bold">E-mailide saatmine</div>
        </div>
      </div>
    </div>
    """
  end

  ## ---------- features · chapter break: contacts ----------

  defp f_part_contacts(assigns) do
    ~H"""
    <.chapter label="Kontaktid" />
    """
  end

  ## ---------- features · the alternatives ----------

  defp f_alternatives(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">Kolm valikut, üks katab kõik.</h2>

      <div class="d-card overflow-hidden mt-[3cqw]">
        <div class="grid grid-cols-[1.3fr_1fr_1fr_1fr_1fr]">
          <div class="d-cardhead"></div>
          <div class="d-cardhead">Käsitsi</div>
          <div class="d-cardhead">Äripäev</div>
          <div class="d-cardhead">Apollo</div>
          <div class="d-cardhead text-accent" style="background:var(--accentSoft);">Liid</div>

          <.crow label="Värske info" a={:yes} b={:partial} c={:no} d={:yes} />
          <.crow label="Eesti firmad" a={:yes} b={:yes} c={:partial} d={:yes} />
          <.crow label="Välismaa firmad" a={:yes} b={:no} c={:yes} d={:yes} />
          <.crow label="Kiiresti palju kontakte" a={:no} b={:yes} c={:yes} d={:yes} last />
        </div>
      </div>
    </div>
    """
  end

  ## ---------- features · the whole enrichment run ----------

  # The map before the walk-through: the same steps the next three slides take
  # one at a time. Sub-lines are examples here, because this slide is answering
  # "what happens", where `s_targeting` answers "how much does it cut".
  defp f_process(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">Riigiregistrist õige inimeseni.</h2>

      <%!-- One row, registries included: the whole point is that this is a
            single run from a state register to a named person, and a row that
            wraps reads as two separate things happening. The countries are
            small and two-up because they are the input to the row, not a step
            of it, and shrinking them is what keeps five boxes on one line.

            Step labels only. The next three slides each take one of these
            apart, so anything explaining them here is said twice. --%>
      <div class="grid grid-cols-[1.25fr_auto_1fr_auto_1fr_auto_1fr_auto_1fr] gap-[0.55cqw] items-stretch mt-[3.2cqw]">
        <div class="d-card px-[0.9cqw] py-[1.2cqw] h-full flex flex-col items-center gap-[0.8cqw]">
          <span class="d-fine text-inkFaint font-semibold uppercase tracking-[0.06em] text-center">
            Äriregistrid
          </span>
          <div class="grid grid-cols-2 gap-[0.35cqw] w-full">
            <span
              :for={c <- ~w(Eesti Läti Leedu Soome Rootsi Norra)}
              class="d-chip justify-center"
              style="background:var(--bgSoft);border:1px solid var(--border);color:var(--inkSoft);font-size:0.82cqw;padding:0.28cqw 0.4cqw;"
            >
              {c}
            </span>
          </div>
        </div>

        <span class="d-h4 text-inkFaint self-center">→</span>
        <.pstep no="1" label="Filter" />
        <span class="d-h4 text-inkFaint self-center">→</span>
        <.pstep no="2" label="Kodulehe otsing" />
        <span class="d-h4 text-inkFaint self-center">→</span>
        <.pstep no="3" label="AI sihtgrupi kontroll" />
        <span class="d-h4 text-inkFaint self-center">→</span>
        <.pstep no="4" label="AI korjab kontaktid" />
      </div>
    </div>
    """
  end

  ## ---------- features · registry + filters ----------

  # No heading on purpose: the slide is one number narrowing to a smaller one,
  # which lands faster than any sentence about it would.
  defp f_filter(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center items-center h-full">
      <div class="text-center">
        <div class="d-fine text-inkFaint">Eesti firmad registris</div>
        <div class="d-num text-ink">{approx(ee_total(@countries, @registry_total))}</div>
      </div>

      <div class="d-h4 text-inkFaint my-[1.4cqw]">↓</div>

      <div class="flex flex-col gap-[1.4cqw] w-[38cqw]">
        <.frow label="Tegevusala" value="Tarkvara · 62.01" />
        <.slider label="Töötajate arv" value="10 – 50" from={18} to={46} />
        <.slider label="Käive" value="€1M – €10M" from={30} to={62} />
      </div>

      <div class="d-h4 text-inkFaint my-[1.4cqw]">↓</div>

      <div class="text-center">
        <div class="d-fine text-inkFaint">Alles</div>
        <div class="d-num text-accent">512</div>
      </div>
    </div>
    """
  end

  ## ---------- features · website validation ----------

  defp f_validate(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">Liid loeb iga kodulehe läbi.</h2>

      <div class="grid grid-cols-[1fr_auto_1.15fr] gap-[2cqw] items-center mt-[3.2cqw]">
        <.stat label="Sobib tegevusala" value="512" />

        <.fork gap="1.2cqw" />

        <div class="grid grid-rows-2 gap-[1.2cqw]">
          <.stat label="Kodukas vastab sihtgrupile" value="128" tone={:accent} />
          <.stat label="Kodukas ei vasta sihtgrupile" value="384" tone={:red} />
        </div>
      </div>
    </div>
    """
  end

  ## ---------- features · finding the right person ----------

  defp f_contacts(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">Ja leiab firmast õige inimese.</h2>

      <div class="grid grid-cols-2 gap-[2.4cqw] mt-[3.2cqw] items-center">
        <div class="flex flex-col gap-[0.9cqw]">
          <.rung no="1" name="Omanik" />
          <.rung no="2" name="Ametinimetus" />
          <.rung no="3" name="Üldkontakt" />
        </div>

        <div class="d-card px-[1.6cqw] py-[1.6cqw] flex items-center gap-[1.2cqw]">
          <span class="d-avatar">MK</span>
          <div>
            <div class="d-h4 font-bold text-ink">Mari Kask</div>
            <div class="d-fine text-inkFaint mt-[0.3cqw]">Müügijuht · datastack.ee</div>
            <div class="d-fine text-green mt-[0.5cqw] flex items-center gap-[0.4cqw]">
              <span class="d-dot bg-green" /> aadress kontrollitud
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  ## ---------- features · chapter break: sending ----------

  defp f_part_sending(assigns) do
    ~H"""
    <.chapter label="E-mailide saatmine" />
    """
  end

  ## ---------- features · the sending funnel ----------

  defp f_sending(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">Kontakt läheb meilide lehtrisse.</h2>

      <%!-- Sequence on top, the three places a contact can end up underneath.
            Counts are deliberately absent: the point is that every contact
            lands in exactly one of them, not how many did. --%>
      <div class="flex flex-col items-center mt-[2.6cqw]">
        <%!-- The sequence is one contact's path, so it stays narrow and
              centred; the outcomes are the whole list fanning out, so they take
              the full width. One arrow per outcome, splaying outward, because a
              single arrow would read as "then all three happen". --%>
        <div class="flex flex-col gap-[0.8cqw] w-[44cqw]">
          <.seqstep label="1. kiri" when_="kohe" tone={:accent} />
          <.seqstep label="2. kiri" when_="+3 päeva" />
          <.seqstep label="3. kiri" when_="+5 päeva" />
        </div>

        <div class="grid grid-cols-3 gap-[1.4cqw] w-full py-[1cqw]">
          <span class="d-h3 text-inkFaint text-center">↙</span>
          <span class="d-h3 text-inkFaint text-center">↓</span>
          <span class="d-h3 text-inkFaint text-center">↘</span>
        </div>

        <div class="grid grid-cols-3 gap-[1.4cqw] w-full">
          <.outcome label="Kõneks valmis" tone={:accent} />
          <.outcome label="Huvitatud" tone={:green} />
          <.outcome label="Ei ole huvitatud" />
        </div>
      </div>
    </div>
    """
  end

  ## ---------- features · the AI learns your writing ----------

  defp f_writing(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">AI ei ole hea kirjutaja, ta on hea jäljendaja.</h2>

      <div class="flex flex-col gap-[1.1cqw] mt-[3.2cqw]">
        <.letter head="Sina kirjutasid" name="Mari" saw="e-pood" fix="kliendiandmete töötlemise" />
        <.letter
          head="AI kirjutas"
          name="Jaan"
          saw="uudiskirja liitumisvorm"
          fix="nõusolekute kogumise"
          tone={:accent}
        />
        <.letter
          head="AI kirjutas"
          name="Kadri"
          saw="tööpakkumiste vorm"
          fix="kandidaatide andmete hoidmise"
          tone={:accent}
        />
      </div>
    </div>
    """
  end

  ## ---------- features · domains and inboxes ----------

  # The same picture as `s_volume`, under a different sentence: there it is the
  # rule you have to obey, here it is what the product does for you.
  defp f_volume(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">Mitu domeeni, igal domeenil mitu aadressi.</h2>
      <.inbox_math />
    </div>
    """
  end

  ## ---------- features · replies ----------

  defp f_reply(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">Edasi sinu moodi.</h2>

      <div class="grid grid-cols-[1fr_auto_1fr] gap-[2cqw] items-center mt-[3.2cqw]">
        <div class="d-card px-[1.6cqw] py-[2.2cqw] text-center" style={tone_style(:green)}>
          <div class="d-h3 font-bold" style={ink_style(:green)}>Kontakt on huvitatud</div>
        </div>

        <.fork gap="1.2cqw" />

        <div class="grid grid-rows-2 gap-[1.2cqw]">
          <div class="d-card px-[1.6cqw] py-[1.6cqw] text-center">
            <div class="d-h4 font-bold text-accent">Suhtle Liidis</div>
          </div>
          <div class="d-card px-[1.6cqw] py-[1.6cqw] text-center">
            <div class="d-h4 font-bold">Ekspordi Pipedrive'i</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  ## ---------- features · summary ----------

  # The whole pitch in two lines: the right contacts, and mail that arrives.
  # Everything else the deck showed is a means to one of those two, so listing
  # features here only competes with them.
  defp f_summary(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">Kaks asja, mis loevad.</h2>

      <div class="flex flex-col gap-[1.2cqw] mt-[3cqw] w-[58cqw] mx-auto">
        <div class="d-card px-[2cqw] py-[1.8cqw]">
          <div class="d-h3 font-bold">
            Leiab kontaktid, kes päriselt sinu sihtgruppi sobivad
          </div>
        </div>
        <div class="d-card px-[2cqw] py-[1.8cqw]">
          <div class="d-h3 font-bold">Saadab kirjad automaatselt ja maitsekalt</div>
        </div>
      </div>

      <%!-- Deliberately not a third card: deliverability is not a third thing
            Liid does, it is what you get out of doing the two above it
            properly. --%>
      <div class="d-lead text-inkSoft mt-[2.4cqw] text-center">
        ja lisaks ei lähe meilid spämmi
      </div>
    </div>
    """
  end

  ## ---------- solving_emails · cover ----------

  defp s_cover(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full text-center">
      <div class="d-kicker text-accent">Liid</div>
      <h1 class="d-h1 mt-[1.6cqw] max-w-[74cqw] mx-auto">
        Kuidas AI ajastul mitte spämmi sattuda.
      </h1>

      <div class="mt-[3.4cqw]">
        <button type="button" data-deck-start phx-click="start" class="d-btn mx-auto">
          ▶ Alusta
        </button>
      </div>

      <div class="d-fine text-inkFaint mt-[1.6cqw]">
        {@slide_count} slaidi · umbes {@minutes} min
      </div>
    </div>
    """
  end

  ## ---------- solving_emails · what changed ----------

  defp s_intro(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">10 000 kirja korraga ei tööta enam.</h2>

      <div class="flex flex-col gap-[1cqw] mt-[3.4cqw] w-[52cqw] mx-auto">
        <.ot job="Osta suur nimekiri" />
        <.ot job="Saada kõik korraga välja" />
        <.ot job="Loota, et keegi vastab" />
      </div>
    </div>
    """
  end

  ## ---------- solving_emails · the risk ----------

  # Two headings on one slide, which nothing else in the deck does. The domain
  # damage is technical and recoverable; the second block is the one that is
  # not, and folding it into the first row would read as three more of the same
  # kind of harm. They are different kinds.
  defp s_risk(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">Riskid oma domeeniga.</h2>

      <div class="grid grid-cols-3 gap-[1.4cqw] mt-[2.2cqw]">
        <.harm title="Google ei leia sind" />
        <.harm title="AI ei soovita sind" />
        <.harm title="Tavakirjad ei jõua kohale" />
      </div>

      <h2 class="d-h2 mt-[3.4cqw]">Ja oma mainega.</h2>

      <div class="grid grid-cols-3 gap-[1.4cqw] mt-[2.2cqw]">
        <.harm title="Turg on väike, kliente piiratud arv" />
        <.harm title="Halb kiri põletab kontakti ära" />
        <.harm title="Sind mäletatakse spämmijana" />
      </div>
    </div>
    """
  end

  ## ---------- solving_emails · the three rules ----------

  defp s_rules(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">Kolm reeglit.</h2>

      <div class="flex flex-col gap-[1.2cqw] mt-[3.4cqw]">
        <.rule no="1">
          Saada
          <.hl>ainult</.hl>
          neile, kes päriselt võiks osta.
        </.rule>
        <.rule no="2">Saada kiri, mille oled ise kirjutanud.</.rule>
        <.rule no="3">Kasuta tänapäevaseid saatmise taktikaid.</.rule>
      </div>
    </div>
    """
  end

  ## ---------- solving_emails · rule 1 ----------

  defp s_targeting(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">1. Saada ainult neile, kes päriselt võiks osta.</h2>

      <%!-- One column, not two. The steps and the counts were the same three
            things listed twice, so the count lives in the step that produced
            it and the row reads as "this filter, this many left". --%>
      <div class="flex flex-col gap-[0.9cqw] mt-[3cqw] w-[62cqw] mx-auto">
        <%!-- Step 0, not step 1: the registries are what the funnel starts
              from, not something Liid does. It is also the only place this deck
              says which countries are covered, which `f_process` carries for
              the other one. --%>
        <.rung
          no="0"
          name="Riiklikud äriregistrid"
          sub="Eesti · Läti · Leedu · Soome · Rootsi · Norra"
          value={approx(@registry_total)}
          unit="firmat"
        />
        <.rung
          no="1"
          name="Tegevusala filter"
          sub="tegevusala · töötajad · käive"
          value="512"
          unit="firmat"
        />
        <.rung
          no="2"
          name="AI sihtgrupi kontroll"
          sub="loeb kodulehe läbi"
          value="128"
          unit="firmat"
        />
        <.rung
          no="3"
          name="AI korjab kontaktid"
          sub="nimi, roll, e-mail kodulehelt"
          value="96"
          unit="kontakti"
          tone={:accent}
        />
      </div>
    </div>
    """
  end

  ## ---------- solving_emails · rule 2 ----------

  defp s_voice(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">2. Kiri peab olema inimlik.</h2>

      <%!-- The letter pair from the features deck's f_writing, compact: same
            sentence, different thing read off each company's own site. --%>
      <div class="grid grid-cols-[1.15fr_1fr] gap-[3cqw] mt-[3.2cqw] items-center">
        <div class="flex flex-col gap-[0.9cqw]">
          <.rung no="1" name="Sina kirjutad esimesed kirjad" />
          <.rung no="2" name="AI õpib sinu käekirjast" />
          <.rung no="3" name="AI kohandab firma eripäradele" />
        </div>

        <div class="flex flex-col gap-[1cqw]">
          <.letter
            compact
            head="Sina kirjutasid"
            name="Mari"
            saw="e-pood"
            fix="kliendiandmete töötlemise"
          />
          <.letter
            compact
            head="AI kirjutas"
            name="Jaan"
            saw="uudiskirja liitumisvorm"
            fix="nõusolekute kogumise"
            tone={:accent}
          />
          <.letter
            compact
            head="AI kirjutas"
            name="Kadri"
            saw="tööpakkumiste vorm"
            fix="kandidaatide andmete hoidmise"
            tone={:accent}
          />
        </div>
      </div>
    </div>
    """
  end

  ## ---------- solving_emails · rule 3 ----------

  defp s_volume(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">3. Kuni 20 kirja päevas ühelt aadressilt.</h2>
      <.inbox_math />
    </div>
    """
  end

  ## ---------- solving_emails · summary ----------

  defp s_summary(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <div class="w-[46cqw] mx-auto">
        <h2 class="d-h2">Liid.</h2>

        <div class="flex flex-col gap-[1.2cqw] mt-[3cqw]">
          <div class="d-card px-[2cqw] py-[1.8cqw]">
            <div class="d-h3 font-bold">Leiab õiged firmad</div>
          </div>
          <div class="d-card px-[2cqw] py-[1.8cqw]">
            <div class="d-h3 font-bold">Saadab e-mailid nii, et nad jõuavad kohale</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  ## ---------- shared close ----------

  defp cta(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <h2 class="d-h2">Mis edasi soovid teha?</h2>

      <div class="flex flex-col gap-[1.1cqw] mt-[3.4cqw] w-[60cqw] mx-auto">
        <.choice kind="call_request" label="Tahan, et Krister helistaks mulle" />
        <.choice kind="try_it" label="Registreerun tasuta ja proovin ise" />
        <.choice kind="not_a_fit" label="Liid pole päris see, mis mul vaja" />
      </div>
    </div>
    """
  end

  ## ---------- pieces ----------

  attr :kind, :string, required: true
  attr :label, :string, required: true
  attr :tone, :atom, default: :plain

  defp choice(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="cta_choice"
      phx-value-kind={@kind}
      class="d-card px-[1.8cqw] py-[1.6cqw] text-left cursor-pointer flex items-center justify-between gap-[1.4cqw]"
      style={ring_style(@tone)}
    >
      <span class="d-h4 font-bold" style={ink_style(@tone)}>{@label}</span>
      <span class="d-h4 shrink-0" style={ink_style(@tone)}>→</span>
    </button>
    """
  end

  attr :label, :string, required: true
  attr :a, :atom, required: true
  attr :b, :atom, required: true
  attr :c, :atom, required: true
  attr :d, :atom, required: true
  attr :last, :boolean, default: false

  defp crow(assigns) do
    ~H"""
    <div class={["d-body text-inkSoft px-[1.5cqw] py-[1cqw]", !@last && "border-b border-border"]}>
      {@label}
    </div>
    <.cmark v={@a} last={@last} />
    <.cmark v={@b} last={@last} />
    <.cmark v={@c} last={@last} />
    <.cmark v={@d} last={@last} accent />
    """
  end

  attr :v, :atom, required: true
  attr :last, :boolean, default: false
  attr :accent, :boolean, default: false

  defp cmark(assigns) do
    ~H"""
    <div
      class={[
        "px-[1.5cqw] py-[1cqw] flex items-center",
        !@last && "border-b border-border"
      ]}
      style={@accent && "background:var(--accentSoft);"}
    >
      <span class={["d-body font-bold", mark_class(@v)]}>{mark_glyph(@v)}</span>
    </div>
    """
  end

  defp mark_glyph(:yes), do: "✓"
  defp mark_glyph(:partial), do: "~"
  defp mark_glyph(:no), do: "✕"

  # Both negatives are red: the point of the table is what the alternatives
  # can't do, and a faint grey mark doesn't carry that at slide distance.
  defp mark_class(:yes), do: "text-green"
  defp mark_class(:partial), do: "text-red"
  defp mark_class(:no), do: "text-red"

  # The arrows of a left-to-right fork. Rendered as a two-row grid with the same
  # gap as the branch column beside it, so each arrow lines up with its own box
  # by grid arithmetic rather than hand-tuned offsets.
  attr :gap, :string, default: "1.2cqw"

  defp fork(assigns) do
    ~H"""
    <div class="grid grid-rows-2 h-full items-center" style={"gap:#{@gap};"}>
      <span class="d-h3 text-inkFaint">↗</span>
      <span class="d-h3 text-inkFaint">↘</span>
    </div>
    """
  end

  # A static copy of the campaign filter's dual-range slider (see
  # `ColtWeb.Campaigns.FiltersLive.range_fset/1`): grey track, accent segment
  # between the two thumbs. Not interactive — it is a picture of the control the
  # viewer will meet after registering, so it should keep looking like it.
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :from, :integer, required: true
  attr :to, :integer, required: true

  defp slider(assigns) do
    ~H"""
    <div>
      <div class="flex items-baseline justify-between">
        <span class="d-fine text-inkFaint font-semibold uppercase tracking-[0.06em]">{@label}</span>
        <span class="d-body font-semibold text-ink tabular-nums">{@value}</span>
      </div>

      <div class="relative mt-[0.8cqw]" style="height:1.3cqw;">
        <div
          class="absolute left-0 right-0 top-1/2 -translate-y-1/2 rounded-full"
          style="height:0.38cqw;background:var(--border);"
        />
        <div
          class="absolute top-1/2 -translate-y-1/2 rounded-full"
          style={"left:#{@from}%;right:#{100 - @to}%;height:0.38cqw;background:var(--accent);"}
        />
        <span
          :for={pct <- [@from, @to]}
          class="absolute top-1/2 -translate-y-1/2 -translate-x-1/2 rounded-full"
          style={"left:#{pct}%;width:1.3cqw;height:1.3cqw;background:var(--card);border:0.2cqw solid var(--accent);"}
        />
      </div>
    </div>
    """
  end

  attr :head, :string, required: true
  attr :name, :string, required: true
  attr :saw, :string, required: true
  attr :fix, :string, required: true
  attr :tone, :atom, default: :plain
  attr :compact, :boolean, default: false

  # One skeleton, three different observations. The sentence around them is
  # identical on purpose: what varies is not a merge field but something read
  # off each company's own site — and `fix` follows from `saw`, which is the
  # part a merge field cannot do.
  #
  # The sender in the example is a GDPR law firm, so every pairing stays inside
  # one trade. Mixed-industry examples read as three unrelated products.
  #
  # Keep the observations to things a homepage or the registry actually states.
  # An example built on hiring news or funding rounds promises signal we do not
  # collect, and the first prospect who asks where it came from is owed a
  # straight answer.
  defp letter(assigns) do
    ~H"""
    <div
      class={[
        "d-card px-[1.6cqw] py-[1.2cqw]",
        !@compact && "flex items-baseline gap-[1.4cqw]"
      ]}
      style={tone_style(@tone)}
    >
      <span class={[
        "d-fine font-semibold uppercase tracking-[0.06em] shrink-0",
        !@compact && "w-[9cqw]",
        @compact && "block mb-[0.5cqw]"
      ]}>
        {@head}
      </span>
      <span class="d-body text-inkSoft leading-[1.5]">
        Tere <.hl>{@name}</.hl>! Nägin, et teil on <.hl>{@saw}</.hl>, aitame teil
        <.hl>{@fix}</.hl>
        korda teha.
      </span>
    </div>
    """
  end

  slot :inner_block, required: true

  # `phx-no-format` is load-bearing: the formatter breaks a long span onto its
  # own lines, and that newline becomes real whitespace *inside* the highlight,
  # which renders as a stray gap before the punctuation that follows ("Mari !").
  defp hl(assigns) do
    ~H"""
    <span phx-no-format class="font-semibold" style="color:var(--accent);">{render_slot(@inner_block)}</span>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp frow(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-[1cqw] bg-bgSoft border border-border rounded-[8px] px-[1.1cqw] py-[0.85cqw]">
      <span class="d-fine text-inkFaint font-semibold uppercase tracking-[0.06em]">{@label}</span>
      <span class="d-body font-semibold text-ink tabular-nums">{@value}</span>
    </div>
    """
  end

  attr :no, :string, required: true
  attr :name, :string, required: true
  attr :sub, :string, default: nil
  attr :value, :string, default: nil
  attr :unit, :string, default: nil
  attr :tone, :atom, default: :plain

  # `sub` is a tidbit, not a sentence: what the step actually looks at, in three
  # or four words. `value` is what the step leaves behind, pinned to the far
  # edge so three rows read as one narrowing column. Both optional — the rungs
  # that name a person's role (`f_contacts`) have neither.
  defp rung(assigns) do
    ~H"""
    <div class="flex items-center gap-[1cqw] d-card px-[1.4cqw] py-[1.1cqw]" style={ring_style(@tone)}>
      <span class="d-step-no shrink-0">{@no}</span>
      <div class="min-w-0">
        <div class="d-h4 font-semibold text-ink">{@name}</div>
        <div :if={@sub} class="d-fine text-inkFaint mt-[0.25cqw]">{@sub}</div>
      </div>
      <div :if={@value} class="ml-auto text-right shrink-0">
        <div class="d-num-sm" style={ink_style(@tone)}>{@value}</div>
        <div :if={@unit} class="d-fine text-inkFaint">{@unit}</div>
      </div>
    </div>
    """
  end

  attr :no, :string, required: true
  slot :inner_block, required: true

  # A slot rather than a string attr so a rule can highlight the word it turns
  # on ("ainult"), which is the whole of rule 1.
  defp rule(assigns) do
    ~H"""
    <div class="d-card flex items-center gap-[1.4cqw] px-[1.8cqw] py-[1.3cqw]">
      <span class="d-step-no shrink-0" style={tone_style(:accent)}>{@no}</span>
      <span class="d-lead text-ink">{render_slot(@inner_block)}</span>
    </div>
    """
  end

  attr :title, :string, required: true

  defp harm(assigns) do
    ~H"""
    <div class="d-card px-[1.4cqw] py-[1.5cqw] flex items-center gap-[0.9cqw]">
      <span class="d-x">✕</span>
      <div class="d-h4 font-bold">{@title}</div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :tone, :atom, default: :plain

  defp outcome(assigns) do
    ~H"""
    <div class="d-card px-[1.4cqw] py-[1.6cqw] text-center" style={tone_style(@tone)}>
      <span class="d-h4 font-bold" style={ink_style(@tone)}>{@label}</span>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :when_, :string, required: true
  attr :tone, :atom, default: :plain

  # A full-width row rather than a centred tile: the sequence stacks in one
  # column, so the timing reads best pinned to the opposite edge from the label.
  defp seqstep(assigns) do
    ~H"""
    <div
      class="border rounded-[8px] px-[1.4cqw] py-[1cqw] flex items-baseline justify-between"
      style={tone_style(@tone) || "border-color:var(--border);background:var(--bgSoft);"}
    >
      <span class="d-h4 font-semibold" style={ink_style(@tone)}>{@label}</span>
      <span class="d-body text-inkFaint">{@when_}</span>
    </div>
    """
  end

  attr :job, :string, required: true

  defp ot(assigns) do
    ~H"""
    <div class="d-card flex items-center gap-[1cqw] px-[1.4cqw] py-[1.2cqw] opacity-[0.85]">
      <span class="d-x">✕</span>
      <span class="d-h4 font-medium text-inkSoft">{@job}</span>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :tone, :atom, default: :plain

  defp stat(assigns) do
    ~H"""
    <div class="d-card px-[1.4cqw] py-[1.4cqw]" style={tone_style(@tone)}>
      <div class="d-fine text-inkSoft font-semibold">{@label}</div>
      <div class="d-num mt-[0.3cqw]" style={ink_style(@tone)}>{@value}</div>
    </div>
    """
  end

  attr :no, :string, required: true
  attr :label, :string, required: true

  # A step in `f_process`'s chain. Full height with the number pinned to the
  # top, so four steps with one- and three-word labels still line up.
  defp pstep(assigns) do
    ~H"""
    <div class="d-card px-[0.9cqw] py-[1.2cqw] h-full flex flex-col items-center text-center gap-[0.6cqw]">
      <span class="d-step-no shrink-0">{@no}</span>
      <span class="d-h4 font-semibold">{@label}</span>
    </div>
    """
  end

  # The arithmetic behind sending volume: how many addresses a daily number
  # costs you. Both decks show it, under different headings — `s_volume` as the
  # rule itself, `f_volume` as what the product does about it — so the picture
  # lives here once and only the sentence above it changes.
  defp inbox_math(assigns) do
    ~H"""
    <div class="grid grid-cols-[1fr_auto_1fr] gap-[3cqw] items-center mt-[2.4cqw]">
      <div class="text-right">
        <div class="d-h1" style="font-size:8.5cqw;">180</div>
        <div class="d-lead text-inkSoft">e-kirja päevas</div>
      </div>

      <div class="d-h1 text-inkFaint" style="font-size:5cqw;">=</div>

      <%!-- Nine addresses, not a number saying nine. What the rule costs you
            in setup is the thing worth showing, and stacking them in one
            equal-width column is what makes the count read at a glance. --%>
      <div class="w-[20cqw]">
        <div class="d-fine text-inkFaint font-semibold uppercase tracking-[0.06em] mb-[0.7cqw]">
          9 saatja aadressi
        </div>
        <div class="flex flex-col gap-[0.45cqw]">
          <span :for={a <- inboxes()} class="d-inbox block">{a}</span>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true

  # A chapter break: one word, one box, nothing else. It exists to mark that the
  # subject changed, so it has to look nothing like the slides either side of
  # it — a heading and a visual would read as another point being made.
  defp chapter(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center items-center h-full">
      <div class="d-card w-[64cqw] px-[3cqw] py-[3.4cqw] text-center">
        <div class="d-h1 text-ink" style="font-size:4.6cqw;">{@label}</div>
      </div>
    </div>
    """
  end

  ## ---------- helpers ----------

  # Tone overrides go through inline style rather than utility classes: the
  # `d-*` slide styles are a plain stylesheet, so a class would lose the
  # specificity fight while an inline style always wins.
  defp tone_style(:accent),
    do: "background:var(--accentSoft);border-color:var(--accentRing);color:var(--accent);"

  defp tone_style(:green),
    do: "background:var(--greenSoft);border-color:#bfe3d1;color:var(--green);"

  defp tone_style(:red),
    do: "background:var(--redSoft);border-color:#f0cdc8;color:var(--red);"

  defp tone_style(_), do: nil

  defp ring_style(:accent), do: "border-color:var(--accentRing);"
  defp ring_style(:green), do: "border-color:#bfe3d1;"
  defp ring_style(:red), do: "border-color:#f0cdc8;"
  defp ring_style(_), do: nil

  defp ink_style(:accent), do: "color:var(--accent);"
  defp ink_style(:green), do: "color:var(--green);"
  defp ink_style(:red), do: "color:var(--red);"
  defp ink_style(_), do: nil

  defp approx(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp approx(n) when n >= 1_000, do: "#{div(n, 1000)}k"
  defp approx(n), do: to_string(n)

  # Three domains, three inboxes each. Grouped by row so the 3×3 grid reads as
  # "three of these, three times" rather than nine unrelated addresses.
  defp inboxes do
    for domain <- ~w(liid.ee liidmail.ee liidapp.ee),
        user <- ~w(krister tiina info),
        do: "#{user}@#{domain}"
  end

  # The filter slide talks about Estonia specifically. Falls back to the
  # all-markets total so the slide still shows a real number in the studio
  # preview, which renders without country data.
  defp ee_total(countries, fallback) do
    case Enum.find(countries, &(&1.name == "Estonia")) do
      %{count: n} when is_integer(n) and n > 0 -> n
      _ -> fallback
    end
  end
end
