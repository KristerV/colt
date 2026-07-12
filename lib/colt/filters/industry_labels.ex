defmodule Colt.Filters.IndustryLabels do
  @moduledoc """
  EMTAK / NACE Rev. 2 code → bilingual label.

  Each level (class / group / division) maps a code to `{en, et}`. The first
  4 digits of an EMTAK 5-digit code are NACE Rev. 2; the 5th digit is a
  national subclass that doesn't change the wording, so we label off the
  NACE class.

  Lookup order (`label/1`): 4-digit class → 3-digit group → 2-digit division.
  Returns the English label by default; `label/2` takes `:en` or `:et`.

  Search (`search/2`) matches the query as a code prefix or as a substring
  in either the English or Estonian label.

  Sources: NACE Rev. 2 EN from KeyteqLabs/node-nace-codes (615 classes /
  272 groups / 88 divisions); ET from EMTAK 2008 selgitavad märkused
  (PRIA mirror). Regenerate with `priv/scripts/gen_industry_labels.exs`.
  """

  @classes %{
    "0111" =>
      {"Growing of cereals (except rice), leguminous crops and oil seeds",
       "Teravilja- (v.a riis), kaunvilja- ja õlitaimeseemnete kasvatus"},
    "0112" => {"Growing of rice", "Riisikasvatus"},
    "0113" =>
      {"Growing of vegetables and melons, roots and tubers",
       "Köögivilja- ja melonikasvatus, juurvilja- ja mugulviljakasvatus"},
    "0114" => {"Growing of sugar cane", "Suhkrurookasvatus"},
    "0115" => {"Growing of tobacco", "Tubakakasvatus"},
    "0116" => {"Growing of fibre crops", "Kiutaimekasvatus"},
    "0119" => {"Growing of other non-perennial crops", "Muude põllukultuuride kasvatus"},
    "0121" => {"Growing of grapes", "Viinamarjakasvatus"},
    "0122" =>
      {"Growing of tropical and subtropical fruits",
       "Troopiliste ja subtroopiliste viljade kasvatus"},
    "0123" => {"Growing of citrus fruits", "Tsitruseliste kasvatus"},
    "0124" =>
      {"Growing of pome fruits and stone fruits", "Õun- ja luuviljaliste puuviljade kasvatus"},
    "0125" =>
      {"Growing of other tree and bush fruits and nuts",
       "Muu puuvilja-, marja- ning pähklikasvatus"},
    "0126" => {"Growing of oleaginous fruits", "Õlitaimekasvatus"},
    "0127" => {"Growing of beverage crops", "Joogitaimekasvatus"},
    "0128" =>
      {"Growing of spices, aromatic, drug and pharmaceutical crops",
       "Vürtsi-, maitse-, uimastavate taimede ja ravimtaimede kasvatus"},
    "0129" => {"Growing of other perennial crops", "Muude mitmeaastaste taimede kasvatus"},
    "0130" => {"Plant propagation", "Taimede paljundamine"},
    "0141" => {"Raising of dairy cattle", "Piimakarjakasvatus"},
    "0142" => {"Raising of other cattle and buffaloes", "Muu veislaste ja pühvlikasvatus"},
    "0143" =>
      {"Raising of horses and other equines", "Hobusekasvatus ja muude hobuslaste kasvatus"},
    "0144" => {"Raising of camels and camelids", "Kaamelikasvatus"},
    "0145" => {"Raising of sheep and goats", "Lamba- ja kitsekasvatus"},
    "0146" => {"Raising of swine/pigs", "Seakasvatus"},
    "0147" => {"Raising of poultry", "Kodulinnukasvatus"},
    "0149" => {"Raising of other animals", "Muu loomakasvatus"},
    "0150" => {"Mixed farming", "Segapõllumajandus"},
    "0161" => {"Support activities for crop production", "Taimekasvatuse abitegevused"},
    "0162" => {"Support activities for animal production", "Loomakasvatuse abitegevused"},
    "0163" => {"Post-harvest crop activities", "Saagikoristusjärgsed tegevused"},
    "0164" => {"Seed processing for propagation", "Seemnete töötlemine paljundamiseks"},
    "0170" =>
      {"Hunting, trapping and related service activities",
       "Jahindus ja seda teenindavad tegevusalad"},
    "0210" =>
      {"Silviculture and other forestry activities",
       "Metsakasvatus ja muud metsamajanduse tegevusalad"},
    "0220" => {"Logging", "Metsavarumine"},
    "0230" =>
      {"Gathering of wild growing non-wood products", "Looduslike materjalide kogumine, v.a puit"},
    "0240" => {"Support services to forestry", "Metsamajandust abistavad tegevused"},
    "0311" => {"Marine fishing", "Merekalapüük"},
    "0312" => {"Freshwater fishing", "Mageveekalapüük"},
    "0321" => {"Marine aquaculture", "Mere-vesiviljelus"},
    "0322" => {"Freshwater aquaculture", "Magevee-vesiviljelus"},
    "0510" => {"Mining of hard coal", "Kivisöe kaevandamine"},
    "0520" => {"Mining of lignite", "Pruunsöe kaevandamine"},
    "0610" => {"Extraction of crude petroleum", "Toornafta tootmine"},
    "0620" => {"Extraction of natural gas", "Maagaasi tootmine"},
    "0710" => {"Mining of iron ores", "Rauamaagi kaevandamine"},
    "0721" => {"Mining of uranium and thorium ores", "Uraani- ja tooriumimaagi kaevandamine"},
    "0729" =>
      {"Mining of other non-ferrous metal ores", "Muude mitteraudmetallide maakide kaevandamine"},
    "0811" =>
      {"Quarrying of ornamental and building stone, limestone, gypsum, chalk and slate",
       "Dekoratiiv- ja ehituskivi, lubjakivi, kipsi, kriidi ja kiltkivi kaevandamine"},
    "0812" =>
      {"Operation of gravel and sand pits; mining of clays and kaolin",
       "Kruusa- ja liivakarjääride tegevus; savi ja kaoliini kaevandamine"},
    "0891" =>
      {"Mining of chemical and fertiliser minerals",
       "Kemikaalide ja mineraalväetiste toorme kaevandamine"},
    "0892" => {"Extraction of peat", "Turba tootmine"},
    "0893" => {"Extraction of salt", "Soola kaevandamine"},
    "0899" => {"Other mining and quarrying n.e.c.", "Muu mujal liigitamata kaevandamine"},
    "0910" =>
      {"Support activities for petroleum and natural gas extraction",
       "Nafta ja maagaasi tootmist abistavad tegevusalad"},
    "0990" =>
      {"Support activities for other mining and quarrying",
       "Muud kaevandamist abistavad tegevusalad"},
    "1011" => {"Processing and preserving of meat", "Liha töötlemine ja säilitamine"},
    "1012" =>
      {"Processing and preserving of poultry meat", "Linnuliha töötlemine ja säilitamine"},
    "1013" =>
      {"Production of meat and poultry meat products", "Liha- ja linnulihatoodete tootmine"},
    "1020" =>
      {"Processing and preserving of fish, crustaceans and molluscs",
       "Kala, vähilaadsete ja limuste töötlemine ja säilitamine"},
    "1031" => {"Processing and preserving of potatoes", "Kartuli töötlemine ja säilitamine"},
    "1032" => {"Manufacture of fruit and vegetable juice", "Puu- ja köögiviljamahla tootmine"},
    "1039" =>
      {"Other processing and preserving of fruit and vegetables",
       "Muu puu- ja köögivilja töötlemine ja säilitamine"},
    "1041" => {"Manufacture of oils and fats", "Õli ja rasva tootmine"},
    "1042" =>
      {"Manufacture of margarine and similar edible fats", "Margariini jms toidurasva tootmine"},
    "1051" =>
      {"Operation of dairies and cheese making",
       "Piima töötlemine, piimatoodete ja juustu tootmine"},
    "1052" => {"Manufacture of ice cream", "Jäätisetootmine"},
    "1061" => {"Manufacture of grain mill products", "Jahu ja tangainete tootmine"},
    "1062" =>
      {"Manufacture of starches and starch products", "Tärklise ja tärklisetoodete tootmine"},
    "1071" =>
      {"Manufacture of bread; manufacture of fresh pastry goods and cakes",
       "Leivatootmine; säilitusaineteta pagaritoodete tootmine"},
    "1072" =>
      {"Manufacture of rusks and biscuits; manufacture of preserved pastry goods and cakes",
       "Kuiviku- ja küpsisetootmine; säilitusainetega pagaritoodete tootmine"},
    "1073" =>
      {"Manufacture of macaroni, noodles, couscous and similar farinaceous products",
       "Makaronide, nuudlite, kuskussi jms makarontoodete tootmine"},
    "1081" => {"Manufacture of sugar", "Suhkrutootmine"},
    "1082" =>
      {"Manufacture of cocoa, chocolate and sugar confectionery",
       "Kakao, šokolaadi ja suhkrukondiitritoodete tootmine"},
    "1083" => {"Processing of tea and coffee", "Tee ja kohvi töötlemine"},
    "1084" => {"Manufacture of condiments and seasonings", "Maitseainete ja -kastmete tootmine"},
    "1085" => {"Manufacture of prepared meals and dishes", "Valmistoitude tootmine"},
    "1086" =>
      {"Manufacture of homogenised food preparations and dietetic food",
       "Homogeenitud toiduainete ja dieettoitude tootmine"},
    "1089" =>
      {"Manufacture of other food products n.e.c.", "Mujal liigitamata toiduainete tootmine"},
    "1091" =>
      {"Manufacture of prepared feeds for farm animals", "Valmissööda tootmine loomakasvatusele"},
    "1092" => {"Manufacture of prepared pet foods", "Lemmikloomade valmistoidu tootmine"},
    "1101" =>
      {"Distilling, rectifying and blending of spirits",
       "Kange alkoholi destilleerimine, rektifitseerimine ja segamine"},
    "1102" => {"Manufacture of wine from grape", "Viinamarjaveini tootmine"},
    "1103" =>
      {"Manufacture of cider and other fruit wines",
       "Siidri ja muu marja- ja puuviljaveini tootmine"},
    "1104" =>
      {"Manufacture of other non-distilled fermented beverages",
       "Muude destilleerimata kääritatud jookide tootmine"},
    "1105" => {"Manufacture of beer", "Õlletootmine"},
    "1106" => {"Manufacture of malt", "Linnasetootmine"},
    "1107" =>
      {"Manufacture of soft drinks; production of mineral waters and other bottled waters",
       "Alkoholivaba joogi tootmine; mineraalvee ja muu villitud vee tootmine"},
    "1200" => {"Manufacture of tobacco products", "Tubakatoodete tootmine"},
    "1310" =>
      {"Preparation and spinning of textile fibres",
       "Tekstiilkiudude ettevalmistamine ja ketramine"},
    "1320" => {"Weaving of textiles", "Riidekudumine"},
    "1330" => {"Finishing of textiles", "Tekstiili viimistlemine"},
    "1391" =>
      {"Manufacture of knitted and crocheted fabrics",
       "Silmkoe- ja heegelkanga (trikookanga) tootmine"},
    "1392" =>
      {"Manufacture of made-up textile articles, except apparel",
       "Valmis tekstiiltoodete tootmine, v.a rõivad"},
    "1393" => {"Manufacture of carpets and rugs", "Vaipade ja vaipkatete tootmine"},
    "1394" =>
      {"Manufacture of cordage, rope, twine and netting", "Nööri, köie ja võrgulina tootmine"},
    "1395" =>
      {"Manufacture of non-wovens and articles made from non-wovens, except apparel",
       "Lausriide ja lausriidest toodete tootmine, v.a rõivad"},
    "1396" =>
      {"Manufacture of other technical and industrial textiles",
       "Tehnilise ja tööstusliku otstarbega tekstiilide tootmine"},
    "1399" => {"Manufacture of other textiles n.e.c.", "Mujal liigitamata tekstiilitootmine"},
    "1411" => {"Manufacture of leather clothes", "Nahkrõivaste tootmine"},
    "1412" => {"Manufacture of workwear", "Töörõivaste tootmine"},
    "1413" => {"Manufacture of other outerwear", "Muude pealisrõivaste tootmine"},
    "1414" => {"Manufacture of underwear", "Alusrõivaste tootmine"},
    "1419" =>
      {"Manufacture of other wearing apparel and accessories",
       "Muude rõivaste ja rõivalisandite tootmine"},
    "1420" => {"Manufacture of articles of fur", "Karusnahatoodete tootmine"},
    "1431" => {"Manufacture of knitted and crocheted hosiery", "Suka- ja sokitootmine"},
    "1439" =>
      {"Manufacture of other knitted and crocheted apparel",
       "Muude silmkoe- ja heegelrõivaste tootmine"},
    "1511" =>
      {"Tanning and dressing of leather; dressing and dyeing of fur",
       "Nahatöötlemine ja -parkimine; karusnaha töötlemine ja värvimine"},
    "1512" =>
      {"Manufacture of luggage, handbags and the like, saddlery and harness",
       "Kohvrite, käekottide, sadulsepatoodete, rakmete jms tootmine"},
    "1520" => {"Manufacture of footwear", "Jalatsitootmine"},
    "1610" => {"Sawmilling and planing of wood", "Puidu saagimine ja hööveldamine"},
    "1621" =>
      {"Manufacture of veneer sheets and wood-based panels", "Spooni ja puitplaatide tootmine"},
    "1622" => {"Manufacture of assembled parquet floors", "Kilpparketi tootmine"},
    "1623" =>
      {"Manufacture of other builders' carpentry and joinery",
       "Ehituspuusepa- ja tisleritoodete tootmine"},
    "1624" => {"Manufacture of wooden containers", "Puittaara tootmine"},
    "1629" =>
      {"Manufacture of other products of wood; manufacture of articles of cork, straw and plaiting materials",
       "Muude puittoodete tootmine; korgist, õlest ja punumismaterjalist toodete"},
    "1711" => {"Manufacture of pulp", "Paberimassi tootmine"},
    "1712" => {"Manufacture of paper and paperboard", "Paberi- ja papitootmine"},
    "1721" =>
      {"Manufacture of corrugated paper and paperboard and of containers of paper and paperboard",
       "Lainepaberi ja -papi ning paber- ja papptaara tootmine"},
    "1722" =>
      {"Manufacture of household and sanitary goods and of toilet requisites",
       "Paberist kodu- ja hügieenitarvete ning tualettpaberi tootmine"},
    "1723" => {"Manufacture of paper stationery", "Paberist kirjatarvete tootmine"},
    "1724" => {"Manufacture of wallpaper", "Tapeeditootmine"},
    "1729" =>
      {"Manufacture of other articles of paper and paperboard",
       "Muude paber- ja papptoodete tootmine"},
    "1811" => {"Printing of newspapers", "Ajalehtede trükkimine"},
    "1812" => {"Other printing", "Muu trükkimine"},
    "1813" => {"Pre-press and pre-media services", "Trükieelne tegevus"},
    "1814" => {"Binding and related services", "Köitmine ja selle sidusalad"},
    "1820" => {"Reproduction of recorded media", "Salvestiste paljundus"},
    "1910" => {"Manufacture of coke oven products", "Koksitootmine"},
    "1920" => {"Manufacture of refined petroleum products", "Puhastatud naftatoodete tootmine"},
    "2011" => {"Manufacture of industrial gases", "Tööstusgaaside tootmine"},
    "2012" => {"Manufacture of dyes and pigments", "Värvainete ja pigmentide tootmine"},
    "2013" =>
      {"Manufacture of other inorganic basic chemicals",
       "Muude anorgaaniliste põhikemikaalide tootmine"},
    "2014" =>
      {"Manufacture of other organic basic chemicals",
       "Muude orgaaniliste põhikemikaalide tootmine"},
    "2015" =>
      {"Manufacture of fertilisers and nitrogen compounds",
       "Väetiste ja lämmastikuühendite tootmine"},
    "2016" => {"Manufacture of plastics in primary forms", "Plasti tootmine algkujul"},
    "2017" =>
      {"Manufacture of synthetic rubber in primary forms",
       "Sünteeskautšuki (toorkummi) tootmine algkujul"},
    "2020" =>
      {"Manufacture of pesticides and other agrochemical products",
       "Taimekaitsevahendite ja muude agrokeemiatoodete tootmine"},
    "2030" =>
      {"Manufacture of paints, varnishes and similar coatings, printing ink and mastics",
       "Värvide, lakkide ja muude viimistlusvahendite ning trükivärvide ja"},
    "2041" =>
      {"Manufacture of soap and detergents, cleaning and polishing preparations",
       "Seebi, pesemis-, puhastus- ja poleervahendite tootmine"},
    "2042" =>
      {"Manufacture of perfumes and toilet preparations", "Parfüümide ja tualetitarvete tootmine"},
    "2051" => {"Manufacture of explosives", "Lõhkeaine tootmine"},
    "2052" => {"Manufacture of glues", "Liimitootmine"},
    "2053" => {"Manufacture of essential oils", "Eeterlike õlide tootmine"},
    "2059" =>
      {"Manufacture of other chemical products n.e.c.",
       "Mujal liigitamata keemiatoodete tootmine"},
    "2060" => {"Manufacture of man-made fibres", "Keemilise kiu tootmine"},
    "2110" => {"Manufacture of basic pharmaceutical products", "Põhifarmaatsiatoodete tootmine"},
    "2120" => {"Manufacture of pharmaceutical preparations", "Ravimpreparaatide tootmine"},
    "2211" =>
      {"Manufacture of rubber tyres and tubes; retreading and rebuilding of rubber tyres",
       "Kummirehvide ja sisekummide tootmine; kummirehvide protekteerimine"},
    "2219" => {"Manufacture of other rubber products", "Muude kummitoodete tootmine"},
    "2221" =>
      {"Manufacture of plastic plates, sheets, tubes and profiles",
       "Plastplaatide, -lehtede, -torude ja -profiilide tootmine"},
    "2222" => {"Manufacture of plastic packing goods", "Plasttaara tootmine"},
    "2223" => {"Manufacture of builders’ ware of plastic", "Plastist ehitustoodete tootmine"},
    "2229" => {"Manufacture of other plastic products", "Muude plasttoodete tootmine"},
    "2311" => {"Manufacture of flat glass", "Lehtklaasi tootmine"},
    "2312" => {"Shaping and processing of flat glass", "Lehtklaasi vormimine ja töötlemine"},
    "2313" => {"Manufacture of hollow glass", "Klaasanumate tootmine"},
    "2314" => {"Manufacture of glass fibres", "Klaaskiutootmine"},
    "2319" =>
      {"Manufacture and processing of other glass, including technical glassware",
       "Muu klaasi tootmine ja töötlemine, sh tehniline klaas"},
    "2320" => {"Manufacture of refractory products", "Tulekindlate toodete tootmine"},
    "2331" =>
      {"Manufacture of ceramic tiles and flags", "Keraamiliste kivide ja plaatide tootmine"},
    "2332" =>
      {"Manufacture of bricks, tiles and construction products, in baked clay",
       "Põletatud savist telliste, kivide ja muude ehitustoodete tootmine"},
    "2341" =>
      {"Manufacture of ceramic household and ornamental articles",
       "Kodu- ja ehiskeraamika tootmine"},
    "2342" =>
      {"Manufacture of ceramic sanitary fixtures", "Keraamiliste sanitaarseadmete tootmine"},
    "2343" =>
      {"Manufacture of ceramic insulators and insulating fittings",
       "Keraamiliste isolaatorite ja isolatsioonielementide tootmine"},
    "2344" =>
      {"Manufacture of other technical ceramic products", "Muu tehnilise keraamika tootmine"},
    "2349" => {"Manufacture of other ceramic products", "Muu keraamika tootmine"},
    "2351" => {"Manufacture of cement", "Tsemenditootmine"},
    "2352" => {"Manufacture of lime and plaster", "Lubja- ja kipsitootmine"},
    "2361" =>
      {"Manufacture of concrete products for construction purposes",
       "Betoonist ehitustoodete tootmine"},
    "2362" =>
      {"Manufacture of plaster products for construction purposes",
       "Kipsist ehitustoodete tootmine"},
    "2363" => {"Manufacture of ready-mixed concrete", "Valmis betoonisegu tootmine"},
    "2364" => {"Manufacture of mortars", "Mörditootmine"},
    "2365" => {"Manufacture of fibre cement", "Kiudtsemendi tootmine"},
    "2369" =>
      {"Manufacture of other articles of concrete, plaster and cement",
       "Muude betoon-, kips- ja tsementtoodete tootmine"},
    "2370" =>
      {"Cutting, shaping and finishing of stone", "Kivilõikamine, -vormimine ja -viimistlus"},
    "2391" => {"Production of abrasive products", "Abrasiivtoodete tootmine"},
    "2399" =>
      {"Manufacture of other non-metallic mineral products n.e.c.",
       "Mujal liigitamata muude mittemetalsetest mineraalidest toodete tootmine"},
    "2410" =>
      {"Manufacture of basic iron and steel and of ferro-alloys",
       "Raua, terase ja ferrosulamite tootmine"},
    "2420" =>
      {"Manufacture of tubes, pipes, hollow profiles and related fittings, of steel",
       "Terastorude, -õõnesprofiilide jms -toruliitmike tootmine"},
    "2431" => {"Cold drawing of bars", "Külmtõmbamine lattideks"},
    "2432" => {"Cold rolling of narrow strip", "Külmvaltsimine kitsasteks ribadeks"},
    "2433" => {"Cold forming or folding", "Külmvormimine ja -painutamine"},
    "2434" => {"Cold drawing of wire", "Traadi külmtõmbamine"},
    "2441" => {"Precious metals production", "Väärismetallitootmine"},
    "2442" => {"Aluminium production", "Alumiiniumitootmine"},
    "2443" => {"Lead, zinc and tin production", "Plii-, tsingi- ja tinatootmine"},
    "2444" => {"Copper production", "Vasetootmine"},
    "2445" => {"Other non-ferrous metal production", "Muude mitteraudmetallide tootmine"},
    "2446" => {"Processing of nuclear fuel", "Tuumkütuse töötlemine"},
    "2451" => {"Casting of iron", "Malmivalu"},
    "2452" => {"Casting of steel", "Terasevalu"},
    "2453" => {"Casting of light metals", "Kergmetallide valu"},
    "2454" => {"Casting of other non-ferrous metals", "Muude mitteraudmetallide valu"},
    "2511" =>
      {"Manufacture of metal structures and parts of structures",
       "Metallkonstruktsioonide ja nende osade tootmine"},
    "2512" => {"Manufacture of doors and windows of metal", "Metalluste ja -akende tootmine"},
    "2521" =>
      {"Manufacture of central heating radiators and boilers",
       "Keskkütteradiaatorite ja -kuumaveekatelde tootmine"},
    "2529" =>
      {"Manufacture of other tanks, reservoirs and containers of metal",
       "Muude metallpaakide, -reservuaaride ja -mahutite tootmine"},
    "2530" =>
      {"Manufacture of steam generators, except central heating hot water boilers",
       "Aurukatelde tootmine, v.a keskkütte-kuumaveekatlad"},
    "2540" => {"Manufacture of weapons and ammunition", "Relva- ja laskemoonatootmine"},
    "2550" =>
      {"Forging, pressing, stamping and roll-forming of metal; powder metallurgy",
       "Metalli sepistamine, pressimine, stantsimine ja rullvaltsimine;"},
    "2561" => {"Treatment and coating of metals", "Metallitöötlus ja metallpindade katmine"},
    "2562" => {"Machining", "Mehaaniline metallitöötlus"},
    "2571" => {"Manufacture of cutlery", "Lõike- ja söögiriistade tootmine"},
    "2572" => {"Manufacture of locks and hinges", "Lukkude ja hingede tootmine"},
    "2573" => {"Manufacture of tools", "Tööriistade tootmine"},
    "2591" =>
      {"Manufacture of steel drums and similar containers", "Terasvaatide jms mahutite tootmine"},
    "2592" => {"Manufacture of light metal packaging", "Kergmetalltaara tootmine"},
    "2593" =>
      {"Manufacture of wire products, chain and springs",
       "Traaditoodete, kettide ja vedrude tootmine"},
    "2594" =>
      {"Manufacture of fasteners and screw machine products",
       "Kinnituselementide ja keermestatud toodete tootmine"},
    "2599" =>
      {"Manufacture of other fabricated metal products n.e.c.",
       "Mujal liigitamata metalltoodete tootmine"},
    "2611" => {"Manufacture of electronic components", "Elektronkomponentide tootmine"},
    "2612" => {"Manufacture of loaded electronic boards", "Trükkplaatide tootmine"},
    "2620" =>
      {"Manufacture of computers and peripheral equipment",
       "Arvutite ja arvuti välisseadmete tootmine"},
    "2630" => {"Manufacture of communication equipment", "Sideseadmete tootmine"},
    "2640" => {"Manufacture of consumer electronics", "Tarbeelektroonika tootmine"},
    "2651" =>
      {"Manufacture of instruments and appliances for measuring, testing and navigation",
       "Mõõte-, katse- ja navigatsiooniseadmete tootmine"},
    "2652" => {"Manufacture of watches and clocks", "Ajanäitajate tootmine"},
    "2660" =>
      {"Manufacture of irradiation, electromedical and electrotherapeutic equipment",
       "Kiiritus-, elektromeditsiini- ja elektroteraapiaseadmete tootmine"},
    "2670" =>
      {"Manufacture of optical instruments and photographic equipment",
       "Optikainstrumentide ja fotoseadmete tootmine"},
    "2680" =>
      {"Manufacture of magnetic and optical media", "Magnet- ja optiliste andmekandjate tootmine"},
    "2711" =>
      {"Manufacture of electric motors, generators and transformers",
       "Elektrimootorite, -generaatorite ja trafode tootmine"},
    "2712" =>
      {"Manufacture of electricity distribution and control apparatus",
       "Elektrijaotusseadmete ja juhtaparatuuri tootmine"},
    "2720" => {"Manufacture of batteries and accumulators", "Patareide ja akude tootmine"},
    "2731" => {"Manufacture of fibre optic cables", "Kiudoptilise kaabli tootmine"},
    "2732" =>
      {"Manufacture of other electronic and electric wires and cables",
       "Muu elektroonika ja elektrijuhtme või -kaabli tootmine"},
    "2733" => {"Manufacture of wiring devices", "Juhtmestiku tarvikute tootmine"},
    "2740" =>
      {"Manufacture of electric lighting equipment", "Elektriliste valgustusseadmete tootmine"},
    "2751" =>
      {"Manufacture of electric domestic appliances", "Elektriliste kodumasinate tootmine"},
    "2752" =>
      {"Manufacture of non-electric domestic appliances",
       "Mitteelektriliste kodumasinate tootmine"},
    "2790" => {"Manufacture of other electrical equipment", "Muude elektriseadmete tootmine"},
    "2811" =>
      {"Manufacture of engines and turbines, except aircraft, vehicle and cycle engines",
       "Mootorite ja turbiinide tootmine, v.a õhusõidukite, mootorsõidukite ja"},
    "2812" =>
      {"Manufacture of fluid power equipment",
       "Hüdrauliliste ja pneumaatiliste jõuseadmete tootmine"},
    "2813" =>
      {"Manufacture of other pumps and compressors", "Muude pumpade ja kompressorite tootmine"},
    "2814" => {"Manufacture of other taps and valves", "Muude kraanide ja ventiilide tootmine"},
    "2815" =>
      {"Manufacture of bearings, gears, gearing and driving elements",
       "Laagrite, ajamite, hammasülekannete ja ülekandeelementide tootmine"},
    "2821" =>
      {"Manufacture of ovens, furnaces and furnace burners",
       "Ahjude, tööstusahjude ja ahjupõletite tootmine"},
    "2822" =>
      {"Manufacture of lifting and handling equipment", "Tõste- ja teisaldusseadmete tootmine"},
    "2823" =>
      {"Manufacture of office machinery and equipment (except computers and peripheral equipment)",
       "Kontorimasinate ja -seadmete tootmine, v.a arvutid ja arvuti välisseadmed"},
    "2824" => {"Manufacture of power-driven hand tools", "Ajamiga käsi-tööriistade tootmine"},
    "2825" =>
      {"Manufacture of non-domestic cooling and ventilation equipment",
       "Tööstuslike külmutus- ja ventilatsiooniseadmete tootmine"},
    "2829" =>
      {"Manufacture of other general-purpose machinery n.e.c.",
       "Mujal liigitamata üldmasinate ja mehhanismide tootmine"},
    "2830" =>
      {"Manufacture of agricultural and forestry machinery",
       "Põllu- ja metsamajandusmasinate tootmine"},
    "2841" => {"Manufacture of metal forming machinery", "Metallistantside tootmine"},
    "2849" => {"Manufacture of other machine tools", "Muude tööpinkide tootmine"},
    "2891" => {"Manufacture of machinery for metallurgy", "Metallurgiamasinate tootmine"},
    "2892" =>
      {"Manufacture of machinery for mining, quarrying and construction",
       "Kaevandus-, karjääri- ja ehitusmasinate tootmine"},
    "2893" =>
      {"Manufacture of machinery for food, beverage and tobacco processing",
       "Toiduaine-, joogi- ja tubakatööstusmasinate tootmine"},
    "2894" =>
      {"Manufacture of machinery for textile, apparel and leather production",
       "Tekstiili-, rõiva- ja nahatööstusmasinate tootmine"},
    "2895" =>
      {"Manufacture of machinery for paper and paperboard production",
       "Paberi- ja papitööstusmasinate tootmine"},
    "2896" =>
      {"Manufacture of plastics and rubber machinery", "Plasti- ja kummitööstusmasinate tootmine"},
    "2899" =>
      {"Manufacture of other special-purpose machinery n.e.c.",
       "Mujal liigitamata erimasinate tootmine"},
    "2910" => {"Manufacture of motor vehicles", "Mootorsõidukite tootmine"},
    "2920" =>
      {"Manufacture of bodies (coachwork) for motor vehicles; manufacture of trailers and semi-trailers",
       "Mootorsõidukikerede tootmine; haagiste ja poolhaagiste tootmine"},
    "2931" =>
      {"Manufacture of electrical and electronic equipment for motor vehicles",
       "Mootorsõidukite elektri- ja elektroonikaseadmete tootmine"},
    "2932" =>
      {"Manufacture of other parts and accessories for motor vehicles",
       "Mootorsõidukite muude osade ja lisaseadmete tootmine"},
    "3011" =>
      {"Building of ships and floating structures", "Laevade ja ujuvkonstruktsioonide ehitus"},
    "3012" => {"Building of pleasure and sporting boats", "Lõbusõidu- ja sportpaatide ehitus"},
    "3020" =>
      {"Manufacture of railway locomotives and rolling stock",
       "Raudteevedurite ja -veeremi tootmine"},
    "3030" =>
      {"Manufacture of air and spacecraft and related machinery",
       "Õhu- ja kosmosesõidukite jms tootmine"},
    "3040" => {"Manufacture of military fighting vehicles", "Militaarveokite tootmine"},
    "3091" => {"Manufacture of motorcycles", "Mootorrataste tootmine"},
    "3092" =>
      {"Manufacture of bicycles and invalid carriages", "Jalgrataste ja invasõidukite tootmine"},
    "3099" =>
      {"Manufacture of other transport equipment n.e.c.",
       "Muude mujal liigitamata transpordivahendite tootmine"},
    "3101" => {"Manufacture of office and shop furniture", "Kontori- ja kauplusemööbli tootmine"},
    "3102" => {"Manufacture of kitchen furniture", "Köögimööbli tootmine"},
    "3103" => {"Manufacture of mattresses", "Madratsitootmine"},
    "3109" => {"Manufacture of other furniture", "Muu mööbli tootmine"},
    "3211" => {"Striking of coins", "Müntide vermimine"},
    "3212" =>
      {"Manufacture of jewellery and related articles", "Väärisesemete jms toodete tootmine"},
    "3213" =>
      {"Manufacture of imitation jewellery and related articles",
       "Juveeltoodete imitatsioonide jms tootmine"},
    "3220" => {"Manufacture of musical instruments", "Muusikariistade tootmine"},
    "3230" => {"Manufacture of sports goods", "Sporditarvete tootmine"},
    "3240" => {"Manufacture of games and toys", "Mängude ja mänguasjade tootmine"},
    "3250" =>
      {"Manufacture of medical and dental instruments and supplies",
       "Meditsiini- ja hambaraviinstrumentide ning materjalide tootmine"},
    "3291" => {"Manufacture of brooms and brushes", "Harja-, pintsli- ja luuatootmine"},
    "3299" => {"Other manufacturing n.e.c.", "Muu mujal liigitamata tootmine"},
    "3311" => {"Repair of fabricated metal products", "Metalltoodete remont"},
    "3312" => {"Repair of machinery", "Masinate ja seadmete remont"},
    "3313" =>
      {"Repair of electronic and optical equipment", "Elektroonika- ja optikaseadmete remont"},
    "3314" => {"Repair of electrical equipment", "Elektriseadmete remont"},
    "3315" =>
      {"Repair and maintenance of ships and boats", "Laevade ja paatide remont ja hooldus"},
    "3316" =>
      {"Repair and maintenance of aircraft and spacecraft",
       "Õhu- ja kosmosesõidukite remont ja hooldus"},
    "3317" =>
      {"Repair and maintenance of other transport equipment",
       "Muude transpordivahendite remont ja hooldus"},
    "3319" => {"Repair of other equipment", "Muude seadmete remont"},
    "3320" =>
      {"Installation of industrial machinery and equipment",
       "Tööstuslike masinate ja seadmete paigaldus"},
    "3511" => {"Production of electricity", "Elektrienergia tootmine"},
    "3512" => {"Transmission of electricity", "Elektrienergia ülekanne"},
    "3513" => {"Distribution of electricity", "Elektrienergia jaotus"},
    "3514" => {"Trade of electricity", "Elektrienergia müük"},
    "3521" => {"Manufacture of gas", "Gaasitootmine"},
    "3522" =>
      {"Distribution of gaseous fuels through mains",
       "Gaaskütuste jaotus magistraalvõrkude kaudu"},
    "3523" => {"Trade of gas through mains", "Gaasimüük magistraalvõrkude kaudu"},
    "3530" =>
      {"Steam and air conditioning supply", "Auru ja konditsioneeritud õhuga varustamine"},
    "3600" => {"Water collection, treatment and supply", "Veekogumine, -töötlus ja -varustus"},
    "3700" => {"Sewerage", "Kanalisatsioon"},
    "3811" => {"Collection of non-hazardous waste", "Tavajäätmete kogumine"},
    "3812" => {"Collection of hazardous waste", "Ohtlike jäätmete kogumine"},
    "3821" =>
      {"Treatment and disposal of non-hazardous waste", "Tavajäätmete töötlus ja kõrvaldus"},
    "3822" =>
      {"Treatment and disposal of hazardous waste", "Ohtlike jäätmete töötlus ja kõrvaldus"},
    "3831" => {"Dismantling of wrecks", "Vrakkide demonteerimine"},
    "3832" => {"Recovery of sorted materials", "Sorteeritud materjali taaskasutusele võtmine"},
    "3900" =>
      {"Remediation activities and other waste management services",
       "Saastekäitlus ja muud jäätmekäitlustegevused"},
    "4110" => {"Development of building projects", "Hoonestusprojektide arendus"},
    "4120" =>
      {"Construction of residential and non-residential buildings",
       "Elamute ja mitteeluhoonete ehitus"},
    "4211" => {"Construction of roads and motorways", "Teede ja kiirteede ehitus"},
    "4212" => {"Construction of railways and underground railways", "Raudteede ja metroo ehitus"},
    "4213" => {"Construction of bridges and tunnels", "Silla- ja tunneliehitus"},
    "4221" =>
      {"Construction of utility projects for fluids",
       "Vee-, gaasi- ja kanalisatsioonitrasside ehitus"},
    "4222" =>
      {"Construction of utility projects for electricity and telecommunications",
       "Elektri- ja sidevõrkude ehitus"},
    "4291" => {"Construction of water projects", "Vesiehitus"},
    "4299" =>
      {"Construction of other civil engineering projects n.e.c.",
       "Mujal liigitamata rajatiste ehitus"},
    "4311" => {"Demolition", "Lammutamine"},
    "4312" => {"Site preparation", "Ehitusplatside ettevalmistus"},
    "4313" => {"Test drilling and boring", "Kontrollpuurimine ja sondimine"},
    "4321" => {"Electrical installation", "Elektriinstallatsioon"},
    "4322" =>
      {"Plumbing, heat and air-conditioning installation",
       "Torustiku, kütte- ja kliimaseadmete paigaldus"},
    "4329" => {"Other construction installation", "Muud ehituspaigaldustööd"},
    "4331" => {"Plastering", "Krohvimine"},
    "4332" => {"Joinery installation", "Ehituspuusepatoodete paigaldus"},
    "4333" => {"Floor and wall covering", "Põranda- ja seinakatete paigaldus"},
    "4334" => {"Painting and glazing", "Värvimine ja klaasimine"},
    "4339" =>
      {"Other building completion and finishing", "Muu ehitiste viimistlus ja lõpetamine"},
    "4391" => {"Roofing activities", "Katusetööd"},
    "4399" =>
      {"Other specialised construction activities n.e.c.", "Muud mujal liigitamata eriehitustööd"},
    "4511" =>
      {"Sale of cars and light motor vehicles",
       "Sõiduautode ja väikebusside (täismassiga alla 3,5 t) müük"},
    "4519" => {"Sale of other motor vehicles", "Muude mootorsõidukite müük"},
    "4520" => {"Maintenance and repair of motor vehicles", "Mootorsõidukite hooldus ja remont"},
    "4531" =>
      {"Wholesale trade of motor vehicle parts and accessories",
       "Mootorsõidukite osade ja lisaseadmete hulgimüük"},
    "4532" =>
      {"Retail trade of motor vehicle parts and accessories",
       "Mootorsõidukite osade ja lisaseadmete jaemüük"},
    "4540" =>
      {"Sale, maintenance and repair of motorcycles and related parts and accessories",
       "Mootorrataste, nende osade ja lisaseadmete müük, hooldus ja remont"},
    "4611" =>
      {"Agents involved in the sale of agricultural raw materials, live animals, textile raw materials and semi-finished goods",
       "Põllumajandustoorme, elusloomade, tekstiilitoorme ja pooltoodete"},
    "4612" =>
      {"Agents involved in the sale of fuels, ores, metals and industrial chemicals",
       "Kütuste, maakide, metallide ja tööstuskemikaalide vahendamine"},
    "4613" =>
      {"Agents involved in the sale of timber and building materials",
       "Puidu ja ehitusmaterjalide vahendamine"},
    "4614" =>
      {"Agents involved in the sale of machinery, industrial equipment, ships and aircraft",
       "Masinate, tööstusseadmete, laevade ja õhusõidukite vahendamine"},
    "4615" =>
      {"Agents involved in the sale of furniture, household goods, hardware and ironmongery",
       "Mööbli, kodutarvete ja rauakaupade vahendamine"},
    "4616" =>
      {"Agents involved in the sale of textiles, clothing, fur, footwear and leather goods",
       "Tekstiili, rõivaste, jalatsite ja nahktoodete vahendamine"},
    "4617" =>
      {"Agents involved in the sale of food, beverages and tobacco",
       "Toidukaupade, jookide ja tubakatoodete vahendamine"},
    "4618" =>
      {"Agents specialised in the sale of other particular products",
       "Muude kindlate kaupade vahendamine"},
    "4619" =>
      {"Agents involved in the sale of a variety of goods",
       "Mitmesuguste erinevate kaupade vahendamine"},
    "4621" =>
      {"Wholesale of grain, unmanufactured tobacco, seeds and animal feeds",
       "Teravilja, töötlemata tubaka, seemnete ja loomasööda hulgimüük"},
    "4622" => {"Wholesale of flowers and plants", "Lillede ja taimede hulgimüük"},
    "4623" => {"Wholesale of live animals", "Elusloomade hulgimüük"},
    "4624" => {"Wholesale of hides, skins and leather", "Toor- ja parknaha hulgimüük"},
    "4631" => {"Wholesale of fruit and vegetables", "Puu- ja köögivilja hulgimüük"},
    "4632" => {"Wholesale of meat and meat products", "Liha ja lihatoodete hulgimüük"},
    "4633" =>
      {"Wholesale of dairy products, eggs and edible oils and fats",
       "Piimatoodete, munade, toiduõli ja -rasva hulgimüük"},
    "4634" => {"Wholesale of beverages", "Jookide hulgimüük"},
    "4635" => {"Wholesale of tobacco products", "Tubakatoodete hulgimüük"},
    "4636" =>
      {"Wholesale of sugar and chocolate and sugar confectionery",
       "Suhkru, šokolaadi ja suhkrukondiitritoodete hulgimüük"},
    "4637" =>
      {"Wholesale of coffee, tea, cocoa and spices",
       "Kohvi, tee, kakao ja maitseainete hulgimüük"},
    "4638" =>
      {"Wholesale of other food, including fish, crustaceans and molluscs",
       "Muude toidukaupade hulgimüük, k.a kalad, vähilaadsed ja limused"},
    "4639" =>
      {"Non-specialised wholesale of food, beverages and tobacco",
       "Toidukaupade, jookide ja tubakatoodete spetsialiseerimata hulgimüük"},
    "4641" => {"Wholesale of textiles", "Tekstiiltoodete hulgimüük"},
    "4642" => {"Wholesale of clothing and footwear", "Rõivaste ja jalatsite hulgimüük"},
    "4643" =>
      {"Wholesale of electrical household appliances", "Elektriliste kodumasinate hulgimüük"},
    "4644" =>
      {"Wholesale of china and glassware and cleaning materials",
       "Portselani ja klaastoodete ning puhastusvahendite hulgimüük"},
    "4645" => {"Wholesale of perfume and cosmetics", "Parfüümide ja kosmeetika hulgimüük"},
    "4646" => {"Wholesale of pharmaceutical goods", "Farmaatsiatoodete hulgimüük"},
    "4647" =>
      {"Wholesale of furniture, carpets and lighting equipment",
       "Mööbli, vaipade ja valgustite hulgimüük"},
    "4648" => {"Wholesale of watches and jewellery", "Kellade ja ehete hulgimüük"},
    "4649" => {"Wholesale of other household goods", "Muude kodutarvete hulgimüük"},
    "4651" =>
      {"Wholesale of computers, computer peripheral equipment and software",
       "Arvutite, arvuti välisseadmete ja tarkvara hulgimüük"},
    "4652" =>
      {"Wholesale of electronic and telecommunications equipment and parts",
       "Elektroonika- ja telekommunikatsiooniseadmete ning nende osade"},
    "4661" =>
      {"Wholesale of agricultural machinery, equipment and supplies",
       "Põllumajandusmasinate, -seadmete ja lisaseadmete hulgimüük"},
    "4662" => {"Wholesale of machine tools", "Tööpinkide hulgimüük"},
    "4663" =>
      {"Wholesale of mining, construction and civil engineering machinery",
       "Kaevandus- ja ehitusmasinate hulgimüük"},
    "4664" =>
      {"Wholesale of machinery for the textile industry and of sewing and knitting machines",
       "Tekstiilitööstus-, õmblus- ja kudumismasinate hulgimüük"},
    "4665" => {"Wholesale of office furniture", "Kontorimööbli hulgimüük"},
    "4666" =>
      {"Wholesale of other office machinery and equipment",
       "Muude kontorimasinate ja -seadmete hulgimüük"},
    "4669" =>
      {"Wholesale of other machinery and equipment", "Muude masinate ja seadmete hulgimüük"},
    "4671" =>
      {"Wholesale of solid, liquid and gaseous fuels and related products",
       "Tahke-, vedel- ja gaaskütuse jms toodete hulgimüük"},
    "4672" => {"Wholesale of metals and metal ores", "Metallide ja metallimaakide hulgimüük"},
    "4673" =>
      {"Wholesale of wood, construction materials and sanitary equipment",
       "Puidu, ehitusmaterjalide ja sanitaarseadmete hulgimüük"},
    "4674" =>
      {"Wholesale of hardware, plumbing and heating equipment and supplies",
       "Rauakaupade, veevarustus- ja kütteseadmete ning nende koosteosade"},
    "4675" => {"Wholesale of chemical products", "Keemiatoodete hulgimüük"},
    "4676" => {"Wholesale of other intermediate products", "Muude vahetoodete hulgimüük"},
    "4677" => {"Wholesale of waste and scrap", "Jäätmete ja jääkide hulgikaubandus"},
    "4690" => {"Non-specialised wholesale trade", "Spetsialiseerimata hulgikaubandus"},
    "4711" =>
      {"Retail sale in non-specialised stores with food, beverages or tobacco predominating",
       "Jaemüük spetsialiseerimata kauplustes, kus on ülekaalus toidukaubad,"},
    "4719" =>
      {"Other retail sale in non-specialised stores",
       "Jaemüük muudes spetsialiseerimata kauplustes"},
    "4721" =>
      {"Retail sale of fruit and vegetables in specialised stores",
       "Puu- ja köögivilja jaemüük spetsialiseeritud kauplustes"},
    "4722" =>
      {"Retail sale of meat and meat products in specialised stores",
       "Liha ja lihatoodete jaemüük spetsialiseeritud kauplustes"},
    "4723" =>
      {"Retail sale of fish, crustaceans and molluscs in specialised stores",
       "Kala, vähilaadsete ja limuste jaemüük spetsialiseeritud kauplustes"},
    "4724" =>
      {"Retail sale of bread, cakes, flour confectionery and sugar confectionery in specialised stores",
       "Leivatoodete, kookide, jahu- ja suhkrukondiitritoodete jaemüük"},
    "4725" =>
      {"Retail sale of beverages in specialised stores",
       "Jookide jaemüük spetsialiseeritud kauplustes"},
    "4726" =>
      {"Retail sale of tobacco products in specialised stores",
       "Tubakatoodete jaemüük spetsialiseeritud kauplustes"},
    "4729" =>
      {"Other retail sale of food in specialised stores",
       "Muu toidukaupade jaemüük spetsialiseeritud kauplustes"},
    "4730" =>
      {"Retail sale of automotive fuel in specialised stores",
       "Mootorikütuse jaemüük spetsialiseeritud kauplustes"},
    "4741" =>
      {"Retail sale of computers, peripheral units and software in specialised stores",
       "Arvutite, arvuti välisseadmete ja tarkvara jaemüük spetsialiseeritud"},
    "4742" =>
      {"Retail sale of telecommunications equipment in specialised stores",
       "Telekommunikatsiooniseadmete jaemüük spetsialiseeritud kauplustes"},
    "4743" =>
      {"Retail sale of audio and video equipment in specialised stores",
       "Heli- ja videoseadmete jaemüük spetsialiseeritud kauplustes"},
    "4751" =>
      {"Retail sale of textiles in specialised stores",
       "Tekstiiltoodete jaemüük spetsialiseeritud kauplustes"},
    "4752" =>
      {"Retail sale of hardware, paints and glass in specialised stores",
       "Rauakaupade, värvide ja klaasi jaemüük spetsialiseeritud kauplustes"},
    "4753" =>
      {"Retail sale of carpets, rugs, wall and floor coverings in specialised stores",
       "Vaipade, mattide, seina- ja põrandakatete jaemüük spetsialiseeritud"},
    "4754" =>
      {"Retail sale of electrical household appliances in specialised stores",
       "Elektriliste kodumasinate jaemüük spetsialiseeritud kauplustes"},
    "4759" =>
      {"Retail sale of furniture, lighting equipment and other household articles in specialised stores",
       "Mööbli, valgustite ja muude kodutarvete jaemüük spetsialiseeritud"},
    "4761" =>
      {"Retail sale of books in specialised stores",
       "Raamatute jaemüük spetsialiseeritud kauplustes"},
    "4762" =>
      {"Retail sale of newspapers and stationery in specialised stores",
       "Ajalehtede ja kirjatarvete jaemüük spetsialiseeritud kauplustes"},
    "4763" =>
      {"Retail sale of music and video recordings in specialised stores",
       "Muusika- ja videosalvestiste jaemüük spetsialiseeritud kauplustes"},
    "4764" =>
      {"Retail sale of sporting equipment in specialised stores",
       "Sporditarvete jaemüük spetsialiseeritud kauplustes"},
    "4765" =>
      {"Retail sale of games and toys in specialised stores",
       "Mängude ja mänguasjade jaemüük spetsialiseeritud kauplustes"},
    "4771" =>
      {"Retail sale of clothing in specialised stores",
       "Rõivaste jaemüük spetsialiseeritud kauplustes"},
    "4772" =>
      {"Retail sale of footwear and leather goods in specialised stores",
       "Jalatsite ja nahktoodete jaemüük spetsialiseeritud kauplustes"},
    "4773" => {"Dispensing chemist in specialised stores", "Apteekide tegevus"},
    "4774" =>
      {"Retail sale of medical and orthopaedic goods in specialised stores",
       "Meditsiini- ja ortopeediakaupade jaemüük spetsialiseeritud kauplustes"},
    "4775" =>
      {"Retail sale of cosmetic and toilet articles in specialised stores",
       "Kosmeetika ja tualetitarvete jaemüük spetsialiseeritud kauplustes"},
    "4776" =>
      {"Retail sale of flowers, plants, seeds, fertilisers, pet animals and pet food in specialised stores",
       "Lillede, taimede, seemnete, väetiste, lemmikloomade ja"},
    "4777" =>
      {"Retail sale of watches and jewellery in specialised stores",
       "Kellade ja ehete jaemüük spetsialiseeritud kauplustes"},
    "4778" =>
      {"Other retail sale of new goods in specialised stores",
       "Muude uute kaupade jaemüük spetsialiseeritud kauplustes"},
    "4779" =>
      {"Retail sale of second-hand goods in stores", "Kasutatud kaupade jaemüük kauplustes"},
    "4781" =>
      {"Retail sale via stalls and markets of food, beverages and tobacco products",
       "Toidukaupade, jookide ja tubakatoodete jaemüük kioskites ja turgudel"},
    "4782" =>
      {"Retail sale via stalls and markets of textiles, clothing and footwear",
       "Tekstiili, rõivaste ja jalatsite jaemüük kioskites ja turgudel"},
    "4789" =>
      {"Retail sale via stalls and markets of other goods",
       "Muude kaupade jaemüük kioskites ja turgudel"},
    "4791" =>
      {"Retail sale via mail order houses or via Internet", "Jaemüük posti või Interneti teel"},
    "4799" =>
      {"Other retail sale not in stores, stalls or markets",
       "Muu jaemüük väljaspool kauplusi, kioskeid ja turge"},
    "4910" => {"Passenger rail transport, interurban", "Sõitjate linnadevaheline raudteevedu"},
    "4920" => {"Freight rail transport", "Kauba raudteevedu"},
    "4931" =>
      {"Urban and suburban passenger land transport",
       "Sõitjate asulasisene ja linnalähitransport"},
    "4932" => {"Taxi operation", "Taksovedu"},
    "4939" =>
      {"Other passenger land transport n.e.c.", "Sõitjate muu mujal liigitamata maismaavedu"},
    "4941" => {"Freight transport by road", "Kaubavedu maanteel"},
    "4942" => {"Removal services", "Kolimisteenused"},
    "4950" => {"Transport via pipeline", "Torutransport"},
    "5010" => {"Sea and coastal passenger water transport", "Sõitjatevedu merel ja rannavetes"},
    "5020" => {"Sea and coastal freight water transport", "Kaubavedu merel ja rannavetes"},
    "5030" => {"Inland passenger water transport", "Sõitjatevedu sisevetel"},
    "5040" => {"Inland freight water transport", "Kaubavedu sisevetel"},
    "5110" => {"Passenger air transport", "Sõitjate õhutransport"},
    "5121" => {"Freight air transport", "Kauba õhutransport"},
    "5122" => {"Space transport", "Kosmosetransport"},
    "5210" => {"Warehousing and storage", "Laondus"},
    "5221" =>
      {"Service activities incidental to land transportation",
       "Maismaaveondust teenindavad tegevusalad"},
    "5222" =>
      {"Service activities incidental to water transportation",
       "Veetransporti teenindavad tegevusalad"},
    "5223" =>
      {"Service activities incidental to air transportation",
       "Õhutransporti teenindavad tegevusalad"},
    "5224" => {"Cargo handling", "Laadungikäitlus"},
    "5229" => {"Other transportation support activities", "Muud veondust abistavad tegevused"},
    "5310" =>
      {"Postal activities under universal service obligation", "Universaalne postiteenus"},
    "5320" => {"Other postal and courier activities", "Muu posti- ja kullerteenus"},
    "5510" => {"Hotels and similar accommodation", "Hotellid ja muu sarnane majutus"},
    "5520" =>
      {"Holiday and other short-stay accommodation", "Puhkuse- ja muu lühiajaline majutus"},
    "5530" =>
      {"Camping grounds, recreational vehicle parks and trailer parks",
       "Laagriplatsid, vagunelamute ja haagissuvilate parkimisplatsid"},
    "5590" => {"Other accommodation", "Muu majutus"},
    "5610" =>
      {"Restaurants and mobile food service activities", "Restoranid ja liikuvad toitlustuskohad"},
    "5621" => {"Event catering activities", "Toitlustamine üritustel"},
    "5629" => {"Other food service activities", "Muu toitlustamine"},
    "5630" => {"Beverage serving activities", "Jookide serveerimine"},
    "5811" => {"Book publishing", "Raamatukirjastamine"},
    "5812" =>
      {"Publishing of directories and mailing lists",
       "Kataloogide ja aadressiraamatute kirjastamine"},
    "5813" => {"Publishing of newspapers", "Ajalehtede kirjastamine"},
    "5814" => {"Publishing of journals and periodicals", "Ajakirjade jm perioodika kirjastamine"},
    "5819" => {"Other publishing activities", "Muu kirjastamine"},
    "5821" => {"Publishing of computer games", "Arvutimängude kirjastamine"},
    "5829" => {"Other software publishing", "Muu tarkvara kirjastamine"},
    "5911" =>
      {"Motion picture, video and television programme production activities",
       "Kinofilmide, videote ja telesaadete tootmine"},
    "5912" =>
      {"Motion picture, video and television programme post-production activities",
       "Kinofilmide, videote ja telesaadete tootmisjärgsed tegevusalad"},
    "5913" =>
      {"Motion picture, video and television programme distribution activities",
       "Kinofilmide, videote ja telesaadete levitamine"},
    "5914" => {"Motion picture projection activities", "Kinofilmide linastamine"},
    "5920" =>
      {"Sound recording and music publishing activities",
       "Helisalvestiste ja muusika kirjastamine"},
    "6010" => {"Radio broadcasting", "Raadioteenused"},
    "6020" =>
      {"Television programming and broadcasting activities",
       "Televisiooniteenused ehk lineaarsed audiovisuaalmeedia teenused"},
    "6110" =>
      {"Wired telecommunications activities",
       "Elektroonilise side teenused fikseeritud sidevõrgus"},
    "6120" =>
      {"Wireless telecommunications activities",
       "Elektroonilise side teenused traadita sidevõrgus"},
    "6130" => {"Satellite telecommunications activities", "Satelliitsideteenused"},
    "6190" => {"Other telecommunications activities", "Elektroonilise side muud teenused"},
    "6201" => {"Computer programming activities", "Programmeerimine"},
    "6202" => {"Computer consultancy activities", "Arvutialased konsultatsioonid"},
    "6203" =>
      {"Computer facilities management activities", "Arvutisüsteemide ja andmebaaside haldus"},
    "6209" =>
      {"Other information technology and computer service activities",
       "Muud infotehnoloogia- ja arvutialased tegevused"},
    "6311" =>
      {"Data processing, hosting and related activities",
       "Andmetöötlus, veebihosting jms tegevused"},
    "6312" => {"Web portals", "Veebiportaalide tegevus"},
    "6391" => {"News agency activities", "Uudisteagentuuride tegevus"},
    "6399" =>
      {"Other information service activities n.e.c.", "Mujal liigitamata infoalane tegevus"},
    "6411" => {"Central banking", "Keskpanga tegevus"},
    "6419" => {"Other monetary intermediation", "Muu rahaloomega seotud finantsvahendus"},
    "6420" => {"Activities of holding companies", "Valdusfirmade tegevus"},
    "6430" =>
      {"Trusts, funds and similar financial entities",
       "Investeerimine võlakirjadesse, väärtpaberitesse jms finantsvahenditesse"},
    "6491" => {"Financial leasing", "Kapitalirent"},
    "6492" => {"Other credit granting", "Muu laenuandmine"},
    "6499" =>
      {"Other financial service activities, except insurance and pension funding n.e.c.",
       "Muude mujal liigitamata finantsteenuste osutamine, v.a kindlustus ja"},
    "6511" => {"Life insurance", "Elukindlustus"},
    "6512" => {"Non-life insurance", "Kahjukindlustus"},
    "6520" => {"Reinsurance", "Edasikindlustus"},
    "6530" => {"Pension funding", "Pensionifondid"},
    "6611" => {"Administration of financial markets", "Finantsturgude haldamine"},
    "6612" =>
      {"Security and commodity contracts brokerage", "Väärtpaberi- ja kaubalepingute maaklerlus"},
    "6619" =>
      {"Other activities auxiliary to financial services, except insurance and pension funding",
       "Muud finantsteenuste abitegevusalad, v.a kindlustus ja pensionifondid"},
    "6621" => {"Risk and damage evaluation", "Riskide ja kahju hindamine"},
    "6622" =>
      {"Activities of insurance agents and brokers", "Kindlustusagentide ja -vahendajate tegevus"},
    "6629" =>
      {"Other activities auxiliary to insurance and pension funding",
       "Muud kindlustuse ja pensionifondide abitegevusalad"},
    "6630" => {"Fund management activities", "Fondide valitsemine"},
    "6810" => {"Buying and selling of own real estate", "Enda kinnisvara ost ja müük"},
    "6820" =>
      {"Renting and operating of own or leased real estate",
       "Enda või renditud kinnisvara üürileandmine ja käitus"},
    "6831" => {"Real estate agencies", "Kinnisvarabüroode tegevus"},
    "6832" =>
      {"Management of real estate on a fee or contract basis",
       "Kinnisvara haldus tasu eest või lepingu alusel"},
    "6910" => {"Legal activities", "Juriidilised toimingud"},
    "6920" =>
      {"Accounting, bookkeeping and auditing activities; tax consultancy",
       "Arvepidamine, raamatupidamine ja auditeerimine; maksualane"},
    "7010" => {"Activities of head offices", "Peakontorite tegevus"},
    "7021" => {"Public relations and communication activities", "Suhtekorraldus ja teabevahetus"},
    "7022" =>
      {"Business and other management consultancy activities",
       "Äri- ja muu juhtimisalane nõustamine"},
    "7111" => {"Architectural activities", "Arhitektitegevused"},
    "7112" =>
      {"Engineering activities and related technical consultancy",
       "Inseneritegevused ning nendega seotud tehniline nõustamine"},
    "7120" => {"Technical testing and analysis", "Teimimine ja analüüs"},
    "7211" =>
      {"Research and experimental development on biotechnology",
       "Teadus- ja arendustegevus biotehnoloogia vallas"},
    "7219" =>
      {"Other research and experimental development on natural sciences and engineering",
       "Teadus- ja arendustegevus muude loodus- ja tehnikateaduste vallas"},
    "7220" =>
      {"Research and experimental development on social sciences and humanities",
       "Teadus- ja arendustegevus sotsiaal- ja humanitaarteaduste vallas"},
    "7311" => {"Advertising agencies", "Reklaamiagentuurid"},
    "7312" => {"Media representation", "Reklaami vahendamine meedias"},
    "7320" =>
      {"Market research and public opinion polling",
       "Turu-uuringud ja avaliku arvamuse küsitlused"},
    "7410" => {"Specialised design activities", "Disainerite tegevus"},
    "7420" => {"Photographic activities", "Fotograafia"},
    "7430" => {"Translation and interpretation activities", "Kirjalik ja suuline tõlge"},
    "7490" =>
      {"Other professional, scientific and technical activities n.e.c.",
       "Muu mujal liigitamata kutse-, teadus- ja tehnikaalane tegevus"},
    "7500" => {"Veterinary activities", "Veterinaaria"},
    "7711" =>
      {"Renting and leasing of cars and light motor vehicles",
       "Sõiduautode ja väikebusside (täismassiga alla 3,5 t) rentimine ja"},
    "7712" => {"Renting and leasing of trucks", "Veokite rentimine ja kasutusrent"},
    "7721" =>
      {"Renting and leasing of recreational and sports goods",
       "Vabaaja- ja sporditarvete väljaüürimine ja kasutusrent"},
    "7722" => {"Renting of video tapes and disks", "Videokassettide ja DVD-de laenutamine"},
    "7729" =>
      {"Renting and leasing of other personal and household goods",
       "Muude tarbeesemete ja kodumasinate väljaüürimine ja kasutusrent"},
    "7731" =>
      {"Renting and leasing of agricultural machinery and equipment",
       "Põllumajandusmasinate ja -seadmete rentimine ja kasutusrent"},
    "7732" =>
      {"Renting and leasing of construction and civil engineering machinery and equipment",
       "Ehitusmasinate ja -seadmete rentimine ja kasutusrent"},
    "7733" =>
      {"Renting and leasing of office machinery and equipment (including computers)",
       "Kontorimasinate ja -seadmete rentimine ja kasutusrent, k.a arvutid"},
    "7734" =>
      {"Renting and leasing of water transport equipment",
       "Veetranspordivahendite rentimine ja kasutusrent"},
    "7735" =>
      {"Renting and leasing of air transport equipment",
       "Õhutranspordivahendite rentimine ja kasutusrent"},
    "7739" =>
      {"Renting and leasing of other machinery, equipment and tangible goods n.e.c.",
       "Mujal liigitamata masinate, seadmete jm materiaalse vara rentimine ja"},
    "7740" =>
      {"Leasing of intellectual property and similar products, except copyrighted works",
       "Intellektuaalomandi ja sarnaste toodete (v.a autoriõigusega tööd)"},
    "7810" => {"Activities of employment placement agencies", "Tööhõiveagentuuride tegevus"},
    "7820" => {"Temporary employment agency activities", "Ajutise tööjõu rent"},
    "7830" => {"Other human resources provision", "Muu inimressursiga varustamine"},
    "7911" => {"Travel agency activities", "Reisibüroode tegevus"},
    "7912" => {"Tour operator activities", "Reisikorraldajate tegevus"},
    "7990" =>
      {"Other reservation service and related activities",
       "Muu reserveerimine ja sellega seotud tegevus"},
    "8010" => {"Private security activities", "Turvatöö, v.a avalik korrakaitse"},
    "8020" => {"Security systems service activities", "Turvasüsteemide käitus"},
    "8030" => {"Investigation activities", "Juurdlus"},
    "8110" => {"Combined facilities support activities", "Hoonehalduse abitegevused"},
    "8121" => {"General cleaning of buildings", "Hoonete üldpuhastus"},
    "8122" =>
      {"Other building and industrial cleaning activities",
       "Hoonete muu puhastus ja tööstuslik puhastustegevus"},
    "8129" => {"Other cleaning activities", "Muu puhastustegevus"},
    "8130" => {"Landscape service activities", "Maastiku hooldus ja korrashoid"},
    "8211" => {"Combined office administrative service activities", "Büroohaldus"},
    "8219" =>
      {"Photocopying, document preparation and other specialised office support activities",
       "Valguskoopiad, dokumentide koostamine ja muud büroo abitegevused"},
    "8220" => {"Activities of call centres", "Kõnekeskuste tegevus"},
    "8230" =>
      {"Organisation of conventions and trade shows", "Nõupidamiste ja messide korraldamine"},
    "8291" =>
      {"Activities of collection agencies and credit bureaus", "Inkassoteenus ja krediidiinfo"},
    "8292" => {"Packaging activities", "Pakendamine"},
    "8299" =>
      {"Other business support service activities n.e.c.",
       "Muud mujal liigitamata äritegevust abistavad tegevused"},
    "8411" => {"General public administration activities", "Üldine avalik haldus"},
    "8412" =>
      {"Regulation of the activities of providing health care, education, cultural services and other social services, excluding social security",
       "Tervishoiu-, haridus-, kultuuriasutuste ja muude sotsiaalteenuste, v.a"},
    "8413" =>
      {"Regulation of and contribution to more efficient operation of businesses",
       "Majandustegevuse korraldamine ja tõhustamine"},
    "8421" => {"Foreign affairs", "Välissuhted"},
    "8422" => {"Defence activities", "Riigikaitse"},
    "8423" => {"Justice and judicial activities", "Õiguskaitse ja kohtud"},
    "8424" =>
      {"Public order and safety activities", "Avalik korrakaitse- ja julgeolekuteenistused"},
    "8425" => {"Fire service activities", "Tuletõrje- ja päästeteenistus"},
    "8430" => {"Compulsory social security activities", "Kohustuslik sotsiaalkindlustus"},
    "8510" => {"Pre-primary education", "Eelharidus"},
    "8520" => {"Primary education", "Esimese taseme haridus"},
    "8531" => {"General secondary education", "Teise taseme üldharidus"},
    "8532" =>
      {"Technical and vocational secondary education", "Teise taseme kutse- ja tehnikaharidus"},
    "8541" => {"Post-secondary non-tertiary education", "Rakenduskõrgharidus"},
    "8542" => {"Tertiary education", "Akadeemiline kõrgharidus"},
    "8551" => {"Sports and recreation education", "Spordi- ja vabaajakoolitus"},
    "8552" => {"Cultural education", "Huvikoolitus"},
    "8553" => {"Driving school activities", "Sõiduõpe"},
    "8559" => {"Other education n.e.c.", "Mujal liigitamata koolitus"},
    "8560" => {"Educational support activities", "Haridust abistavad tegevused"},
    "8610" => {"Hospital activities", "Haiglaravi"},
    "8621" => {"General medical practice activities", "Üldarstiabi"},
    "8622" => {"Specialist medical practice activities", "Eriarstiabi"},
    "8623" => {"Dental practice activities", "Hambaravi"},
    "8690" => {"Other human health activities", "Muud tervishoiualad"},
    "8710" => {"Residential nursing care activities", "Hooldusraviasutuste tegevus"},
    "8720" =>
      {"Residential care activities for mental retardation, mental health and substance abuse",
       "Vaimupuudega ja psüühiliste erivajadustega isikute ning ainesõltlaste"},
    "8730" =>
      {"Residential care activities for the elderly and disabled",
       "Vanurite ja puuetega inimeste hoolekandeasutuste tegevus"},
    "8790" => {"Other residential care activities", "Muude hoolekandeasutuste tegevus"},
    "8810" =>
      {"Social work activities without accommodation for the elderly and disabled",
       "Vanurite ja puuetega inimeste sotsiaalhoolekanne majutuseta"},
    "8891" => {"Child day-care activities", "Lapsehoiuteenus"},
    "8899" =>
      {"Other social work activities without accommodation n.e.c.",
       "Mujal liigitamata sotsiaalhoolekanne majutuseta"},
    "9001" => {"Performing arts", "Lavakunst"},
    "9002" => {"Support activities to performing arts", "Lavakunsti abitegevused"},
    "9003" => {"Artistic creation", "Kunstialane loometegevus"},
    "9004" => {"Operation of arts facilities", "Teatri-, kontserdi- jms hoonete käitus"},
    "9101" => {"Library and archives activities", "Raamatukogude ja arhiivide tegevus"},
    "9102" => {"Museums activities", "Muuseumide tegevus"},
    "9103" =>
      {"Operation of historical sites and buildings and similar visitor attractions",
       "Ajalooliste kohtade ja ehitiste jms vaatamisväärsuste käitus"},
    "9104" =>
      {"Botanical and zoological gardens and nature reserves activities",
       "Botaanika- ja loomaaedade ning looduskaitsealade tegevus"},
    "9200" => {"Gambling and betting activities", "Hasartmängude ja kihlvedude korraldamine"},
    "9311" => {"Operation of sports facilities", "Spordirajatiste käitus"},
    "9312" => {"Activities of sports clubs", "Spordiklubide tegevus"},
    "9313" => {"Fitness facilities", "Aeroobika- ja jõusaalide tegevus"},
    "9319" => {"Other sports activities", "Muu sporditegevus"},
    "9321" =>
      {"Activities of amusement parks and theme parks",
       "Lõbustusparkide ja temaatiliste lõbustusparkide tegevus"},
    "9329" =>
      {"Other amusement and recreation activities", "Muud lõbustus- ja vaba aja tegevused"},
    "9411" =>
      {"Activities of business and employers membership organisations",
       "Ettevõtjate ja tööandjate organisatsioonide tegevus"},
    "9412" =>
      {"Activities of professional membership organisations", "Kutseorganisatsioonide tegevus"},
    "9420" => {"Activities of trade unions", "Ametiühingute tegevus"},
    "9491" => {"Activities of religious organisations", "Usuorganisatsioonide tegevus"},
    "9492" => {"Activities of political organisations", "Poliitiliste organisatsioonide tegevus"},
    "9499" =>
      {"Activities of other membership organisations n.e.c.",
       "Mujal liigitamata organisatsioonide tegevus"},
    "9511" =>
      {"Repair of computers and peripheral equipment",
       "Arvutite ja arvuti välisseadmete parandus"},
    "9512" => {"Repair of communication equipment", "Sideseadmete parandus"},
    "9521" => {"Repair of consumer electronics", "Tarbeelektroonika parandus"},
    "9522" =>
      {"Repair of household appliances and home and garden equipment",
       "Kodumasinate ning majapidamis- ja aiatööriistade parandus"},
    "9523" => {"Repair of footwear and leather goods", "Jalatsite ja nahktoodete parandus"},
    "9524" => {"Repair of furniture and home furnishings", "Mööbli ja sisustusesemete parandus"},
    "9525" => {"Repair of watches, clocks and jewellery", "Kellade ja ehete parandus"},
    "9529" =>
      {"Repair of other personal and household goods",
       "Muude tarbeesemete ja kodutarvete parandus"},
    "9601" =>
      {"Washing and (dry-)cleaning of textile and fur products",
       "Tekstiil- ja karusnahatoodete pesu ja keemiline puhastus"},
    "9602" => {"Hairdressing and other beauty treatment", "Juuksuri- ja muu iluteenindus"},
    "9603" => {"Funeral and related activities", "Matuseteenindus"},
    "9604" => {"Physical well-being activities", "Füüsilise heaoluga seotud teenindus"},
    "9609" => {"Other personal service activities n.e.c.", "Muu mujal liigitamata teenindus"},
    "9700" =>
      {"Activities of households as employers of domestic personnel",
       "Kodumajapidamised majapidamispersonali tööandjana"},
    "9810" =>
      {"Undifferentiated goods-producing activities of private households for own use",
       "Kodumajapidamiste oma tarbeks mõeldud eristamata kaupade tootmine"},
    "9820" =>
      {"Undifferentiated service-producing activities of private households for own use",
       "Kodumajapidamiste oma tarbeks mõeldud eristamata teenuste osutamine"},
    "9900" => {"Activities of extraterritorial organisations and bodies", nil}
  }

  @groups %{
    "011" => {"Growing of non-perennial crops", "Üheaastaste põllukultuuride kasvatus"},
    "012" => {"Growing of perennial crops", "Mitmeaastaste taimede kasvatus"},
    "013" => {"Plant propagation", "Taimede paljundamine"},
    "014" => {"Animal production", "Loomakasvatus"},
    "015" => {"Mixed farming", "Segapõllumajandus"},
    "016" =>
      {"Support activities to agriculture and post-harvest crop activities",
       "Põllumajandust abistavad tegevusalad ja saagikoristusjärgsed"},
    "017" =>
      {"Hunting, trapping and related service activities",
       "Jahindus ja seda teenindavad tegevusalad"},
    "021" =>
      {"Silviculture and other forestry activities",
       "Metsakasvatus ja muud metsamajanduse tegevusalad"},
    "022" => {"Logging", "Metsavarumine"},
    "023" =>
      {"Gathering of wild growing non-wood products", "Looduslike materjalide kogumine, v.a puit"},
    "024" => {"Support services to forestry", "Metsamajandust abistavad tegevused"},
    "031" => {"Fishing", "Kalapüük"},
    "032" => {"Aquaculture", "Vesiviljelus"},
    "051" => {"Mining of hard coal", "Kivisöe kaevandamine"},
    "052" => {"Mining of lignite", "Pruunsöe kaevandamine"},
    "061" => {"Extraction of crude petroleum", "Toornafta tootmine"},
    "062" => {"Extraction of natural gas", "Maagaasi tootmine"},
    "071" => {"Mining of iron ores", "Rauamaagi kaevandamine"},
    "072" => {"Mining of non-ferrous metal ores", "Mitteraudmetallide maakide kaevandamine"},
    "081" => {"Quarrying of stone, sand and clay", "Kivi, liiva ja savi kaevandamine"},
    "089" => {"Mining and quarrying n.e.c.", "Mujal liigitamata kaevandamine"},
    "091" =>
      {"Support activities for petroleum and natural gas extraction",
       "Nafta ja maagaasi tootmist abistavad tegevusalad"},
    "099" =>
      {"Support activities for other mining and quarrying",
       "Muud kaevandamist abistavad tegevusalad"},
    "101" =>
      {"Processing and preserving of meat and production of meat products",
       "Liha töötlemine ja säilitamine ning lihatoodete tootmine"},
    "102" =>
      {"Processing and preserving of fish, crustaceans and molluscs",
       "Kala, vähilaadsete ja limuste töötlemine ja säilitamine"},
    "103" =>
      {"Processing and preserving of fruit and vegetables",
       "Puu- ja köögivilja töötlemine ja säilitamine"},
    "104" =>
      {"Manufacture of vegetable and animal oils and fats",
       "Taimse ja loomse õli ja rasva tootmine"},
    "105" => {"Manufacture of dairy products", "Piimatoodete tootmine"},
    "106" =>
      {"Manufacture of grain mill products, starches and starch products",
       "Jahu ja tangainete, tärklise ja tärklisetoodete tootmine"},
    "107" =>
      {"Manufacture of bakery and farinaceous products", "Pagari- ja makarontoodete tootmine"},
    "108" => {"Manufacture of other food products", "Muude toiduainete tootmine"},
    "109" => {"Manufacture of prepared animal feeds", "Valmis loomasööda tootmine"},
    "110" => {"Manufacture of beverages", "Joogitootmine"},
    "120" => {"Manufacture of tobacco products", "Tubakatoodete tootmine"},
    "131" =>
      {"Preparation and spinning of textile fibres",
       "Tekstiilkiudude ettevalmistamine ja ketramine"},
    "132" => {"Weaving of textiles", "Riidekudumine"},
    "133" => {"Finishing of textiles", "Tekstiili viimistlemine"},
    "139" => {"Manufacture of other textiles", "Muu tekstiilitootmine"},
    "141" =>
      {"Manufacture of wearing apparel, except fur apparel",
       "Rõivatootmine, v.a karusnahast rõivad"},
    "142" => {"Manufacture of articles of fur", "Karusnahatoodete tootmine"},
    "143" =>
      {"Manufacture of knitted and crocheted apparel", "Silmkoe- ja heegelrõivaste tootmine"},
    "151" =>
      {"Tanning and dressing of leather; manufacture of luggage, handbags, saddlery and harness; dressing and dyeing of fur",
       "Nahatöötlemine ja -parkimine; kohvrite, käekottide,"},
    "152" => {"Manufacture of footwear", "Jalatsitootmine"},
    "161" => {"Sawmilling and planing of wood", "Puidu saagimine ja hööveldamine"},
    "162" =>
      {"Manufacture of products of wood, cork, straw and plaiting materials",
       "Puidust, korgist, õlest ja punumismaterjalist toodete tootmine"},
    "171" =>
      {"Manufacture of pulp, paper and paperboard", "Paberimassi, paberi ja papi tootmine"},
    "172" =>
      {"Manufacture of articles of paper and paperboard", "Paber- ja papptoodete tootmine"},
    "181" =>
      {"Printing and service activities related to printing", "Trükindus ja selle sidusalad"},
    "182" => {"Reproduction of recorded media", "Salvestiste paljundus"},
    "191" => {"Manufacture of coke oven products", "Koksitootmine"},
    "192" => {"Manufacture of refined petroleum products", "Puhastatud naftatoodete tootmine"},
    "201" =>
      {"Manufacture of basic chemicals, fertilisers and nitrogen compounds, plastics and synthetic rubber in primary forms",
       "Põhikemikaalide, väetise ja lämmastikuühendite tootmine; plasti ja"},
    "202" =>
      {"Manufacture of pesticides and other agrochemical products",
       "Taimekaitsevahendite ja muude agrokeemiatoodete tootmine"},
    "203" =>
      {"Manufacture of paints, varnishes and similar coatings, printing ink and mastics",
       "Värvide, lakkide ja muude viimistlusvahendite ning trükivärvide ja"},
    "204" =>
      {"Manufacture of soap and detergents, cleaning and polishing preparations, perfumes and toilet preparations",
       "Seebi, pesemis-, puhastus- ja poleervahendite, parfüümide ja"},
    "205" => {"Manufacture of other chemical products", "Muude keemiatoodete tootmine"},
    "206" => {"Manufacture of man-made fibres", "Keemilise kiu tootmine"},
    "211" => {"Manufacture of basic pharmaceutical products", "Põhifarmaatsiatoodete tootmine"},
    "212" => {"Manufacture of pharmaceutical preparations", "Ravimpreparaatide tootmine"},
    "221" => {"Manufacture of rubber products", "Kummitoodete tootmine"},
    "222" => {"Manufacture of plastic products", "Plasttoodete tootmine"},
    "231" => {"Manufacture of glass and glass products", "Klaasi ja klaastoodete tootmine"},
    "232" => {"Manufacture of refractory products", "Tulekindlate toodete tootmine"},
    "233" => {"Manufacture of clay building materials", "Savist ehitusmaterjalide tootmine"},
    "234" =>
      {"Manufacture of other porcelain and ceramic products",
       "Muude portselan- ja keraamikatoodete tootmine"},
    "235" => {"Manufacture of cement, lime and plaster", "Tsemendi-, lubja- ja kipsitootmine"},
    "236" =>
      {"Manufacture of articles of concrete, cement and plaster",
       "Betoon-, tsement- ja kipstoodete tootmine"},
    "237" =>
      {"Cutting, shaping and finishing of stone", "Kivilõikamine, -vormimine ja -viimistlus"},
    "239" =>
      {"Manufacture of abrasive products and non-metallic mineral products n.e.c.",
       "Mujal liigitamata abrasiivtoodete ja mittemetalsetest mineraalidest"},
    "241" =>
      {"Manufacture of basic iron and steel and of ferro-alloys",
       "Raua, terase ja ferrosulamite tootmine"},
    "242" =>
      {"Manufacture of tubes, pipes, hollow profiles and related fittings, of steel",
       "Terastorude, -õõnesprofiilide jms -toruliitmike tootmine"},
    "243" =>
      {"Manufacture of other products of first processing of steel",
       "Muude terase esmatöötlustoodete tootmine"},
    "244" =>
      {"Manufacture of basic precious and other non-ferrous metals",
       "Vääris- ja mitteraudmetallide tootmine"},
    "245" => {"Casting of metals", "Metallivalu"},
    "251" => {"Manufacture of structural metal products", "Metallkonstruktsioonide tootmine"},
    "252" =>
      {"Manufacture of tanks, reservoirs and containers of metal",
       "Metallpaakide, -reservuaaride ja -mahutite tootmine"},
    "253" =>
      {"Manufacture of steam generators, except central heating hot water boilers",
       "Aurukatelde tootmine, v.a keskkütte-kuumaveekatlad"},
    "254" => {"Manufacture of weapons and ammunition", "Relva- ja laskemoonatootmine"},
    "255" =>
      {"Forging, pressing, stamping and roll-forming of metal; powder metallurgy",
       "Metalli sepistamine, pressimine, stantsimine ja rullvaltsimine;"},
    "256" =>
      {"Treatment and coating of metals; machining",
       "Metallitöötlus ja metallpindade katmine; mehaaniline metallitöötlus"},
    "257" =>
      {"Manufacture of cutlery, tools and general hardware",
       "Lõike- ja tööriistade ning rauakaupade tootmine"},
    "259" => {"Manufacture of other fabricated metal products", "Muude metalltoodete tootmine"},
    "261" =>
      {"Manufacture of electronic components and boards",
       "Elektronkomponentide ja trükkplaatide tootmine"},
    "262" =>
      {"Manufacture of computers and peripheral equipment",
       "Arvutite ja arvuti välisseadmete tootmine"},
    "263" => {"Manufacture of communication equipment", "Sideseadmete tootmine"},
    "264" => {"Manufacture of consumer electronics", "Tarbeelektroonika tootmine"},
    "265" =>
      {"Manufacture of instruments and appliances for measuring, testing and navigation; watches and clocks",
       "Mõõte-, katse- ja navigatsiooniseadmete tootmine; ajanäitajate"},
    "266" =>
      {"Manufacture of irradiation, electromedical and electrotherapeutic equipment",
       "Kiiritus-, elektromeditsiini- ja elektroteraapiaseadmete tootmine"},
    "267" =>
      {"Manufacture of optical instruments and photographic equipment",
       "Optikainstrumentide ja fotoseadmete tootmine"},
    "268" =>
      {"Manufacture of magnetic and optical media", "Magnet- ja optiliste andmekandjate tootmine"},
    "271" =>
      {"Manufacture of electric motors, generators, transformers and electricity distribution and control apparatus",
       "Elektrimootorite, -generaatorite, trafode ja elektrijaotusseadmete"},
    "272" => {"Manufacture of batteries and accumulators", "Patareide ja akude tootmine"},
    "273" =>
      {"Manufacture of wiring and wiring devices", "Juhtmestiku ja selle tarvikute tootmine"},
    "274" =>
      {"Manufacture of electric lighting equipment", "Elektriliste valgustusseadmete tootmine"},
    "275" => {"Manufacture of domestic appliances", "Kodumasinate tootmine"},
    "279" => {"Manufacture of other electrical equipment", "Muude elektriseadmete tootmine"},
    "281" => {"Manufacture of general-purpose machinery", "Üldmasinate tootmine"},
    "282" => {"Manufacture of other general-purpose machinery", "Muude üldmasinate tootmine"},
    "283" =>
      {"Manufacture of agricultural and forestry machinery",
       "Põllu- ja metsamajandusmasinate tootmine"},
    "284" =>
      {"Manufacture of metal forming machinery and machine tools",
       "Metallistantside ja muude tööpinkide tootmine"},
    "289" => {"Manufacture of other special-purpose machinery", "Muude erimasinate tootmine"},
    "291" => {"Manufacture of motor vehicles", "Mootorsõidukite tootmine"},
    "292" =>
      {"Manufacture of bodies (coachwork) for motor vehicles; manufacture of trailers and semi-trailers",
       "Mootorsõidukikerede tootmine; haagiste ja poolhaagiste tootmine"},
    "293" =>
      {"Manufacture of parts and accessories for motor vehicles",
       "Mootorsõidukite osade ja lisaseadmete tootmine"},
    "301" => {"Building of ships and boats", "Laeva- ja paadiehitus"},
    "302" =>
      {"Manufacture of railway locomotives and rolling stock",
       "Raudteevedurite ja -veeremi tootmine"},
    "303" =>
      {"Manufacture of air and spacecraft and related machinery",
       "Õhu- ja kosmosesõidukite jms tootmine"},
    "304" => {"Manufacture of military fighting vehicles", "Militaarveokite tootmine"},
    "309" =>
      {"Manufacture of transport equipment n.e.c.",
       "Mujal liigitamata transpordivahendite tootmine"},
    "310" => {"Manufacture of furniture", "Mööblitootmine"},
    "321" =>
      {"Manufacture of jewellery, bijouterie and related articles",
       "Väärisesemete, ehete jms toodete tootmine"},
    "322" => {"Manufacture of musical instruments", "Muusikariistade tootmine"},
    "323" => {"Manufacture of sports goods", "Sporditarvete tootmine"},
    "324" => {"Manufacture of games and toys", "Mängude ja mänguasjade tootmine"},
    "325" =>
      {"Manufacture of medical and dental instruments and supplies",
       "Meditsiini- ja hambaraviinstrumentide ning materjalide tootmine"},
    "329" => {"Manufacturing n.e.c.", "Mujal liigitamata tootmine"},
    "331" =>
      {"Repair of fabricated metal products, machinery and equipment",
       "Metalltoodete, masinate ja seadmete remont"},
    "332" =>
      {"Installation of industrial machinery and equipment",
       "Tööstuslike masinate ja seadmete paigaldus"},
    "351" =>
      {"Electric power generation, transmission and distribution",
       "Elektrienergia tootmine, ülekanne ja jaotus"},
    "352" =>
      {"Manufacture of gas; distribution of gaseous fuels through mains",
       "Gaasitootmine; gaaskütuste jaotus magistraalvõrkude kaudu"},
    "353" => {"Steam and air conditioning supply", "Auru ja konditsioneeritud õhuga varustamine"},
    "360" => {"Water collection, treatment and supply", "Veekogumine, -töötlus ja -varustus"},
    "370" => {"Sewerage", "Kanalisatsioon"},
    "381" => {"Waste collection", "Jäätmekogumine"},
    "382" => {"Waste treatment and disposal", "Jäätmetöötlus ja -kõrvaldus"},
    "383" => {"Materials recovery", "Materjalide taaskasutusele võtmine"},
    "390" =>
      {"Remediation activities and other waste management services",
       "Saastekäitlus ja muud jäätmekäitlustegevused"},
    "411" => {"Development of building projects", "Hoonestusprojektide arendus"},
    "412" =>
      {"Construction of residential and non-residential buildings",
       "Elamute ja mitteeluhoonete ehitus"},
    "421" => {"Construction of roads and railways", "Teede ja raudteede ehitus"},
    "422" => {"Construction of utility projects", "Tehnovõrgutrasside ehitus"},
    "429" => {"Construction of other civil engineering projects", "Muude rajatiste ehitus"},
    "431" => {"Demolition and site preparation", "Lammutamine ja ehitusplatside ettevalmistus"},
    "432" =>
      {"Electrical, plumbing and other construction installation activities",
       "Elektriinstallatsioon ja torustiku paigaldus jm ehituspaigaldustööd"},
    "433" => {"Building completion and finishing", "Ehitiste viimistlus ja lõpetamine"},
    "439" => {"Other specialised construction activities", "Muud eriehitustööd"},
    "451" => {"Sale of motor vehicles", "Mootorsõidukite müük"},
    "452" => {"Maintenance and repair of motor vehicles", "Mootorsõidukite hooldus ja remont"},
    "453" =>
      {"Sale of motor vehicle parts and accessories",
       "Mootorsõidukite osade ja lisaseadmete müük"},
    "454" =>
      {"Sale, maintenance and repair of motorcycles and related parts and accessories",
       "Mootorrataste, nende osade ja lisaseadmete müük, hooldus ja"},
    "461" =>
      {"Wholesale on a fee or contract basis", "Hulgimüük vahendustasu või lepingu alusel"},
    "462" =>
      {"Wholesale of agricultural raw materials and live animals",
       "Põllumajandustoorme ja elusloomade hulgimüük"},
    "463" =>
      {"Wholesale of food, beverages and tobacco",
       "Toidukaupade, jookide ja tubakatoodete hulgimüük"},
    "464" => {"Wholesale of household goods", "Kodutarvete hulgimüük"},
    "465" =>
      {"Wholesale of information and communication equipment", "Info- ja sidetehnika hulgimüük"},
    "466" =>
      {"Wholesale of other machinery, equipment and supplies",
       "Muude masinate, seadmete ja lisaseadmete hulgimüük"},
    "467" => {"Other specialised wholesale", "Muu spetsialiseeritud hulgimüük"},
    "469" => {"Non-specialised wholesale trade", "Spetsialiseerimata hulgikaubandus"},
    "471" => {"Retail sale in non-specialised stores", "Jaemüük spetsialiseerimata kauplustes"},
    "472" =>
      {"Retail sale of food, beverages and tobacco in specialised stores",
       "Toidukaupade, jookide ja tubakatoodete jaemüük spetsialiseeritud"},
    "473" =>
      {"Retail sale of automotive fuel in specialised stores",
       "Mootorikütuse jaemüük spetsialiseeritud kauplustes"},
    "474" =>
      {"Retail sale of information and communication equipment in specialised stores",
       "Info- ja sidetehnika jaemüük spetsialiseeritud kauplustes"},
    "475" =>
      {"Retail sale of other household equipment in specialised stores",
       "Muude kodutarvete jaemüük spetsialiseeritud kauplustes"},
    "476" =>
      {"Retail sale of cultural and recreation goods in specialised stores",
       "Kultuuri- ja vaba aja kaupade jaemüük spetsialiseeritud kauplustes"},
    "477" =>
      {"Retail sale of other goods in specialised stores",
       "Muude kaupade jaemüük spetsialiseeritud kauplustes"},
    "478" => {"Retail sale via stalls and markets", "Jaemüük kioskites ja turgudel"},
    "479" =>
      {"Retail trade not in stores, stalls or markets",
       "Jaemüük väljaspool kauplusi, kioskeid ja turge"},
    "491" => {"Passenger rail transport, interurban", "Sõitjate linnadevaheline raudteevedu"},
    "492" => {"Freight rail transport", "Kauba raudteevedu"},
    "493" => {"Other passenger land transport", "Sõitjate muu maismaavedu"},
    "494" =>
      {"Freight transport by road and removal services", "Kaubavedu maanteel ja kolimisteenused"},
    "495" => {"Transport via pipeline", "Torutransport"},
    "501" => {"Sea and coastal passenger water transport", "Sõitjatevedu merel ja rannavetes"},
    "502" => {"Sea and coastal freight water transport", "Kaubavedu merel ja rannavetes"},
    "503" => {"Inland passenger water transport", "Sõitjatevedu sisevetel"},
    "504" => {"Inland freight water transport", "Kaubavedu sisevetel"},
    "511" => {"Passenger air transport", "Sõitjate õhutransport"},
    "512" =>
      {"Freight air transport and space transport", "Kauba õhutransport ja kosmosetransport"},
    "521" => {"Warehousing and storage", "Laondus"},
    "522" => {"Support activities for transportation", "Veondust abistavad tegevusalad"},
    "531" => {"Postal activities under universal service obligation", "Universaalne postiteenus"},
    "532" => {"Other postal and courier activities", "Muu posti- ja kullerteenus"},
    "551" => {"Hotels and similar accommodation", "Hotellid ja muu sarnane majutus"},
    "552" =>
      {"Holiday and other short-stay accommodation", "Puhkuse- ja muu lühiajaline majutus"},
    "553" =>
      {"Camping grounds, recreational vehicle parks and trailer parks",
       "Laagriplatsid, vagunelamute ja haagissuvilate parkimisplatsid"},
    "559" => {"Other accommodation", "Muu majutus"},
    "561" =>
      {"Restaurants and mobile food service activities", "Restoranid ja liikuvad toitlustuskohad"},
    "562" =>
      {"Event catering and other food service activities",
       "Toitlustamine üritustel jm toitlustamine"},
    "563" => {"Beverage serving activities", "Jookide serveerimine"},
    "581" =>
      {"Publishing of books, periodicals and other publishing activities",
       "Raamatu-, perioodika- jm kirjastamine"},
    "582" => {"Software publishing", "Tarkvara kirjastamine"},
    "591" =>
      {"Motion picture, video and television programme activities",
       "Kinofilmide, videote ja telesaadetega seotud tegevusalad"},
    "592" =>
      {"Sound recording and music publishing activities",
       "Helisalvestiste ja muusika kirjastamine"},
    "601" => {"Radio broadcasting", "Raadioteenused"},
    "602" =>
      {"Television programming and broadcasting activities",
       "Televisiooniteenused ehk lineaarsed audiovisuaalmeedia teenused"},
    "611" => {"Wired telecommunications activities", "Fikseeritud sidevõrgu teenused"},
    "612" => {"Wireless telecommunications activities", "Traadita elektroonilise side teenused"},
    "613" => {"Satellite telecommunications activities", "Satelliitsideteenused"},
    "619" => {"Other telecommunications activities", "Elektroonilise side muud teenused"},
    "620" =>
      {"Computer programming, consultancy and related activities",
       "Programmeerimine, konsultatsioonid jms tegevused"},
    "631" =>
      {"Data processing, hosting and related activities; web portals",
       "Andmetöötlus, veebihosting jms tegevused; veebiportaalide"},
    "639" => {"Other information service activities", "Muu infoalane tegevus"},
    "641" => {"Monetary intermediation", "Rahaloomega seotud finantsvahendus"},
    "642" => {"Activities of holding companies", "Valdusfirmade tegevus"},
    "643" =>
      {"Trusts, funds and similar financial entities",
       "Investeerimine võlakirjadesse, väärtpaberitesse jms"},
    "649" =>
      {"Other financial service activities, except insurance and pension funding",
       "Muude finantsteenuste osutamine, v.a kindlustus ja pensionifondid"},
    "651" => {"Insurance", "Kindlustus"},
    "652" => {"Reinsurance", "Edasikindlustus"},
    "653" => {"Pension funding", "Pensionifondid"},
    "661" =>
      {"Activities auxiliary to financial services, except insurance and pension funding",
       "Finantsteenuste abitegevusalad, v.a kindlustus ja pensionifondid"},
    "662" =>
      {"Activities auxiliary to insurance and pension funding",
       "Kindlustuse ja pensionifondide abitegevusalad"},
    "663" => {"Fund management activities", "Fondide valitsemine"},
    "681" => {"Buying and selling of own real estate", "Enda kinnisvara ost ja müük"},
    "682" =>
      {"Renting and operating of own or leased real estate",
       "Enda või renditud kinnisvara üürileandmine ja käitus"},
    "683" =>
      {"Real estate activities on a fee or contract basis",
       "Kinnisvaraalane tegevus tasu eest või lepingu alusel"},
    "691" => {"Legal activities", "Juriidilised toimingud"},
    "692" =>
      {"Accounting, bookkeeping and auditing activities; tax consultancy",
       "Arvepidamine, raamatupidamine ja auditeerimine; maksualane"},
    "701" => {"Activities of head offices", "Peakontorite tegevus"},
    "702" => {"Management consultancy activities", "Juhtimisalane nõustamine"},
    "711" =>
      {"Architectural and engineering activities and related technical consultancy",
       "Arhitekti- ja inseneritegevused ning nendega seotud tehniline"},
    "712" => {"Technical testing and analysis", "Teimimine ja analüüs"},
    "721" =>
      {"Research and experimental development on natural sciences and engineering",
       "Teadus- ja arendustegevus loodus- ja tehnikateaduste vallas"},
    "722" =>
      {"Research and experimental development on social sciences and humanities",
       "Teadus- ja arendustegevus sotsiaal- ja humanitaarteaduste vallas"},
    "731" => {"Advertising", "Reklaamindus"},
    "732" =>
      {"Market research and public opinion polling",
       "Turu-uuringud ja avaliku arvamuse küsitlused"},
    "741" => {"Specialised design activities", "Disainerite tegevus"},
    "742" => {"Photographic activities", "Fotograafia"},
    "743" => {"Translation and interpretation activities", "Kirjalik ja suuline tõlge"},
    "749" =>
      {"Other professional, scientific and technical activities n.e.c.",
       "Muu mujal liigitamata kutse-, teadus- ja tehnikaalane tegevus"},
    "750" => {"Veterinary activities", "Veterinaaria"},
    "771" =>
      {"Renting and leasing of motor vehicles", "Mootorsõidukite rentimine ja kasutusrent"},
    "772" =>
      {"Renting and leasing of personal and household goods",
       "Tarbeesemete ja kodumasinate väljaüürimine ja kasutusrent"},
    "773" =>
      {"Renting and leasing of other machinery, equipment and tangible goods",
       "Muude masinate, seadmete ja materiaalse vara rentimine ja"},
    "774" =>
      {"Leasing of intellectual property and similar products, except copyrighted works",
       "Intellektuaalomandi ja sarnaste toodete (v.a autoriõigusega tööd)"},
    "781" => {"Activities of employment placement agencies", "Tööhõiveagentuuride tegevus"},
    "782" => {"Temporary employment agency activities", "Ajutise tööjõu rent"},
    "783" => {"Other human resources provision", "Muu inimressursiga varustamine"},
    "791" =>
      {"Travel agency and tour operator activities", "Reisibüroode ja reisikorraldajate tegevus"},
    "799" =>
      {"Other reservation service and related activities",
       "Muu reserveerimine ja sellega seotud tegevus"},
    "801" => {"Private security activities", "Turvatöö, v.a avalik korrakaitse"},
    "802" => {"Security systems service activities", "Turvasüsteemide käitus"},
    "803" => {"Investigation activities", "Juurdlus"},
    "811" => {"Combined facilities support activities", "Hoonehalduse abitegevused"},
    "812" => {"Cleaning activities", "Puhastustegevus"},
    "813" => {"Landscape service activities", "Maastiku hooldus ja korrashoid"},
    "821" =>
      {"Office administrative and support activities", "Büroohaldus ja selle abitegevused"},
    "822" => {"Activities of call centres", "Kõnekeskuste tegevus"},
    "823" =>
      {"Organisation of conventions and trade shows", "Nõupidamiste ja messide korraldamine"},
    "829" =>
      {"Business support service activities n.e.c.",
       "Mujal liigitamata äritegevust abistavad tegevused"},
    "841" =>
      {"Administration of the State and the economic and social policy of the community",
       "Avalik haldus ning majandus- ja sotsiaalpoliitika juhtimine"},
    "842" =>
      {"Provision of services to the community as a whole", "Ühiskonna kui terviku teenindamine"},
    "843" => {"Compulsory social security activities", "Kohustuslik sotsiaalkindlustus"},
    "851" => {"Pre-primary education", "Eelharidus"},
    "852" => {"Primary education", "Esimese taseme haridus"},
    "853" => {"Secondary education", "Teise taseme haridus"},
    "854" => {"Higher education", "Kolmanda taseme haridus"},
    "855" => {"Other education", "Muu koolitus"},
    "856" => {"Educational support activities", "Haridust abistavad tegevused"},
    "861" => {"Hospital activities", "Haiglaravi"},
    "862" => {"Medical and dental practice activities", "Arstiabi ja hambaravi"},
    "869" => {"Other human health activities", "Muud tervishoiualad"},
    "871" => {"Residential nursing care activities", "Hooldusraviasutuste tegevus"},
    "872" =>
      {"Residential care activities for mental retardation, mental health and substance abuse",
       "Vaimupuudega ja psüühiliste erivajadustega isikute ning"},
    "873" =>
      {"Residential care activities for the elderly and disabled",
       "Vanurite ja puuetega inimeste hoolekandeasutuste tegevus"},
    "879" => {"Other residential care activities", "Muude hoolekandeasutuste tegevus"},
    "881" =>
      {"Social work activities without accommodation for the elderly and disabled",
       "Vanurite ja puuetega inimeste sotsiaalhoolekanne majutuseta"},
    "889" =>
      {"Other social work activities without accommodation", "Muu sotsiaalhoolekanne majutuseta"},
    "900" =>
      {"Creative, arts and entertainment activities", "Loome-, kunsti- ja meelelahutustegevus"},
    "910" =>
      {"Libraries, archives, museums and other cultural activities",
       "Raamatukogude, arhiivide, muuseumide ja muude kultuuriasutuste"},
    "920" => {"Gambling and betting activities", "Hasartmängude ja kihlvedude korraldamine"},
    "931" => {"Sports activities", "Sporditegevus"},
    "932" => {"Amusement and recreation activities", "Lõbustus- ja vaba aja tegevused"},
    "941" =>
      {"Activities of business, employers and professional membership organisations",
       "Ettevõtjate, tööandjate ja kutseorganisatsioonide tegevus"},
    "942" => {"Activities of trade unions", "Ametiühingute tegevus"},
    "949" => {"Activities of other membership organisations", "Muude organisatsioonide tegevus"},
    "951" =>
      {"Repair of computers and communication equipment", "Arvutite ja sideseadmete parandus"},
    "952" => {"Repair of personal and household goods", "Tarbeesemete ja kodutarvete parandus"},
    "960" => {"Other personal service activities", "Muu teenindus"},
    "970" =>
      {"Activities of households as employers of domestic personnel",
       "Kodumajapidamised majapidamispersonali tööandjana"},
    "981" =>
      {"Undifferentiated goods-producing activities of private households for own use",
       "Kodumajapidamiste oma tarbeks mõeldud eristamata kaupade"},
    "982" =>
      {"Undifferentiated service-producing activities of private households for own use",
       "Kodumajapidamiste oma tarbeks mõeldud eristamata teenuste"},
    "990" => {"Activities of extraterritorial organisations and bodies", nil}
  }

  @divisions %{
    "01" =>
      {"Crop and animal production, hunting and related service activities",
       "Taime- ja loomakasvatus, jahindus ja neid teenindavad tegevusalad"},
    "02" => {"Forestry and logging", "Metsamajandus ja metsavarumine"},
    "03" => {"Fishing and aquaculture", "Kalapüük ja vesiviljelus"},
    "05" => {"Mining of coal and lignite", "Kivi- ja pruunsöe kaevandamine"},
    "06" => {"Extraction of crude petroleum and natural gas", "Toornafta ja maagaasi tootmine"},
    "07" => {"Mining of metal ores", "Metallimaakide kaevandamine"},
    "08" => {"Other mining and quarrying", "Muu kaevandamine"},
    "09" => {"Mining support service activities", "Kaevandamist abistavad tegevusalad"},
    "10" => {"Manufacture of food products", "Toiduainete tootmine"},
    "11" => {"Manufacture of beverages", "Joogitootmine"},
    "12" => {"Manufacture of tobacco products", "Tubakatoodete tootmine"},
    "13" => {"Manufacture of textiles", "Tekstiilitootmine"},
    "14" => {"Manufacture of wearing apparel", "Rõivatootmine"},
    "15" =>
      {"Manufacture of leather and related products", "Nahatöötlemine ja nahktoodete tootmine"},
    "16" =>
      {"Manufacture of wood and of products of wood and cork, except furniture; manufacture of articles of straw and plaiting materials",
       "Puidutöötlemine ning puit- ja korktoodete tootmine, v.a mööbel;"},
    "17" => {"Manufacture of paper and paper products", "Paberi ja pabertoodete tootmine"},
    "18" => {"Printing and reproduction of recorded media", "Trükindus ja salvestiste paljundus"},
    "19" =>
      {"Manufacture of coke and refined petroleum products",
       "Koksi ja puhastatud naftatoodete tootmine"},
    "20" =>
      {"Manufacture of chemicals and chemical products", "Kemikaalide ja keemiatoodete tootmine"},
    "21" =>
      {"Manufacture of basic pharmaceutical products and pharmaceutical preparations",
       "Põhifarmaatsiatoodete ja ravimpreparaatide tootmine"},
    "22" => {"Manufacture of rubber and plastic products", "Kummi- ja plasttoodete tootmine"},
    "23" =>
      {"Manufacture of other non-metallic mineral products",
       "Muude mittemetalsetest mineraalidest toodete tootmine"},
    "24" => {"Manufacture of basic metals", "Metallitootmine"},
    "25" =>
      {"Manufacture of fabricated metal products, except machinery and equipment",
       "Metalltoodete tootmine, v.a masinad ja seadmed"},
    "26" =>
      {"Manufacture of computer, electronic and optical products",
       "Arvutite, elektroonika- ja optikaseadmete tootmine"},
    "27" => {"Manufacture of electrical equipment", "Elektriseadmete tootmine"},
    "28" =>
      {"Manufacture of machinery and equipment n.e.c.",
       "Mujal liigitamata masinate ja seadmete tootmine"},
    "29" =>
      {"Manufacture of motor vehicles, trailers and semi-trailers",
       "Mootorsõidukite, haagiste ja poolhaagiste tootmine"},
    "30" => {"Manufacture of other transport equipment", "Muude transpordivahendite tootmine"},
    "31" => {"Manufacture of furniture", "Mööblitootmine"},
    "32" => {"Other manufacturing", "Muu tootmine"},
    "33" =>
      {"Repair and installation of machinery and equipment",
       "Masinate ja seadmete remont ja paigaldus"},
    "35" =>
      {"Electricity, gas, steam and air conditioning supply",
       "Elektrienergia, gaasi, auru ja konditsioneeritud õhuga varustamine"},
    "36" => {"Water collection, treatment and supply", "Veekogumine, -töötlus ja -varustus"},
    "37" => {"Sewerage", "Kanalisatsioon"},
    "38" =>
      {"Waste collection, treatment and disposal activities; materials recovery",
       "Jäätmekogumine, -töötlus ja -kõrvaldus; materjalide"},
    "39" =>
      {"Remediation activities and other waste management services",
       "Saastekäitlus ja muud jäätmekäitlustegevused"},
    "41" => {"Construction of buildings", "Hoonete ehitus"},
    "42" => {"Civil engineering", "Rajatiste ehitus"},
    "43" =>
      {"Specialised construction activities",
       "ehitustegevuse raames tehtavad eriehitustööd. Ehitusseadmete rentimine"},
    "45" =>
      {"Wholesale and retail trade and repair of motor vehicles and motorcycles",
       "Mootorsõidukite ja mootorrataste hulgi- ja jaemüük ning remont"},
    "46" =>
      {"Wholesale trade, except of motor vehicles and motorcycles",
       "Hulgikaubandus, v.a mootorsõidukid ja mootorrattad"},
    "47" =>
      {"Retail trade, except of motor vehicles and motorcycles",
       "Jaekaubandus, v.a mootorsõidukid ja mootorrattad"},
    "49" => {"Land transport and transport via pipelines", "Maismaaveondus ja torutransport"},
    "50" => {"Water transport", "Veetransport"},
    "51" => {"Air transport", "Õhutransport"},
    "52" =>
      {"Warehousing and support activities for transportation",
       "Laondus ja veondust abistavad tegevusalad"},
    "53" => {"Postal and courier activities", "Posti- ja kullerteenus"},
    "55" => {"Accommodation", "Majutus"},
    "56" => {"Food and beverage service activities", "Toidu ja joogi serveerimine"},
    "58" => {"Publishing activities", "Kirjastamine"},
    "59" =>
      {"Motion picture, video and television programme production, sound recording and music publishing activities",
       "Kinofilmide, videote ja telesaadete tootmine; helisalvestiste ja"},
    "60" => {"Programming and broadcasting activities", "Meediateenused"},
    "61" => {"Telecommunications", "Elektroonilise side teenus"},
    "62" =>
      {"Computer programming, consultancy and related activities",
       "Programmeerimine, konsultatsioonid jms tegevused"},
    "63" => {"Information service activities", "Infoalane tegevus"},
    "64" =>
      {"Financial service activities, except insurance and pension funding",
       "Finantsteenuste osutamine, v.a kindlustus ja pensionifondid"},
    "65" =>
      {"Insurance, reinsurance and pension funding, except compulsory social security",
       "Kindlustus, edasikindlustus ja pensionifondid, v.a kohustuslik"},
    "66" =>
      {"Activities auxiliary to financial services and insurance activities",
       "Finantsteenuste ja kindlustustegevuse abitegevusalad"},
    "68" => {"Real estate activities", "Kinnisvaraalane tegevus"},
    "69" => {"Legal and accounting activities", "Juriidilised toimingud ja arvepidamine"},
    "70" =>
      {"Activities of head offices; management consultancy activities",
       "Peakontorite tegevus; juhtimisalane nõustamine"},
    "71" =>
      {"Architectural and engineering activities; technical testing and analysis",
       "Arhitekti- ja inseneritegevused; teimimine ja analüüs"},
    "72" => {"Scientific research and development", "Teadus- ja arendustegevus"},
    "73" => {"Advertising and market research", "Reklaamindus ja turu-uuringud"},
    "74" =>
      {"Other professional, scientific and technical activities",
       "Muu kutse-, teadus- ja tehnikaalane tegevus"},
    "75" => {"Veterinary activities", "Veterinaaria"},
    "77" => {"Rental and leasing activities", "Rentimine ja kasutusrent"},
    "78" => {"Employment activities", "Tööhõive"},
    "79" =>
      {"Travel agency, tour operator and other reservation service and related activities",
       "Reisibüroode ja reisikorraldajate tegevus, reserveerimine ning"},
    "80" => {"Security and investigation activities", "Turvatöö ja juurdlus"},
    "81" => {"Services to buildings and landscape activities", "Hoonete ja maastike hooldus"},
    "82" =>
      {"Office administrative, office support and other business support activities",
       "Büroohaldus, büroode ja muu äritegevuse abitegevused"},
    "84" =>
      {"Public administration and defence; compulsory social security",
       "Avalik haldus ja riigikaitse; kohustuslik sotsiaalkindlustus"},
    "85" => {"Education", "Haridus"},
    "86" => {"Human health activities", "Tervishoid"},
    "87" => {"Residential care activities", "Hoolekandeasutuste tegevus"},
    "88" => {"Social work activities without accommodation", "Sotsiaalhoolekanne majutuseta"},
    "90" =>
      {"Creative, arts and entertainment activities", "Loome-, kunsti- ja meelelahutustegevus"},
    "91" =>
      {"Libraries, archives, museums and other cultural activities",
       "Raamatukogude, arhiivide, muuseumide ja muude kultuuriasutuste"},
    "92" => {"Gambling and betting activities", "Hasartmängude ja kihlvedude korraldamine"},
    "93" =>
      {"Sports activities and amusement and recreation activities",
       "Sporditegevus ning lõbustus- ja vaba aja tegevused"},
    "94" => {"Activities of membership organisations", "Organisatsioonide tegevus"},
    "95" =>
      {"Repair of computers and personal and household goods",
       "Arvutite ning tarbeesemete ja kodutarvete parandus"},
    "96" => {"Other personal service activities", "Muu teenindus"},
    "97" =>
      {"Activities of households as employers of domestic personnel",
       "Kodumajapidamised majapidamispersonali tööandjana"},
    "98" =>
      {"Undifferentiated goods- and services-producing activities of private households for own use",
       "Kodumajapidamiste oma tarbeks mõeldud eristamata kaupade"},
    "99" => {"Activities of extraterritorial organisations and bodies", nil}
  }

  def label(code), do: label(code, :en)

  def label(code, lang) when is_binary(code) and lang in [:en, :et] do
    key4 = String.slice(code, 0, 4)
    key3 = String.slice(code, 0, 3)
    key2 = String.slice(code, 0, 2)

    pair =
      Map.get(@classes, key4) ||
        Map.get(@groups, key3) ||
        Map.get(@divisions, key2)

    case {pair, lang} do
      {nil, _} -> nil
      {{en, _}, :en} -> en
      {{en, nil}, :et} -> en
      {{_, et}, :et} -> et
    end
  end

  def label(_, _), do: nil

  @doc """
  Substring/prefix search over the 615 NACE classes. Returns up to `limit`
  `{code, en_label}` pairs. Matches code-prefix first, then substring hits in
  either the English or the Estonian label, ranked by EN-label length.
  """
  def search(query, limit \\ 20) when is_binary(query) do
    q = query |> String.trim() |> String.downcase()

    if q == "" do
      []
    else
      @classes
      |> Enum.reduce([], fn {code, {en, et}}, acc ->
        en_d = String.downcase(en)
        et_d = if et, do: String.downcase(et), else: ""

        cond do
          String.starts_with?(code, q) -> [{0, String.length(en), {code, en}} | acc]
          String.contains?(en_d, q) -> [{1, String.length(en), {code, en}} | acc]
          et_d != "" and String.contains?(et_d, q) -> [{1, String.length(en), {code, en}} | acc]
          true -> acc
        end
      end)
      |> Enum.sort()
      |> Enum.take(limit)
      |> Enum.map(fn {_, _, entry} -> entry end)
    end
  end

  # ── NACE Rev. 2 sections (tree top level). {letter, title, div_lo, div_hi} ──
  @sections [
    {"A", "Agriculture, forestry and fishing", 1, 3},
    {"B", "Mining and quarrying", 5, 9},
    {"C", "Manufacturing", 10, 33},
    {"D", "Electricity, gas, steam and air conditioning supply", 35, 35},
    {"E", "Water supply, sewerage and waste management", 36, 39},
    {"F", "Construction", 41, 43},
    {"G", "Wholesale and retail trade; repair of motor vehicles", 45, 47},
    {"H", "Transportation and storage", 49, 53},
    {"I", "Accommodation and food service activities", 55, 56},
    {"J", "Information and communication", 58, 63},
    {"K", "Financial and insurance activities", 64, 66},
    {"L", "Real estate activities", 68, 68},
    {"M", "Professional, scientific and technical activities", 69, 75},
    {"N", "Administrative and support service activities", 77, 82},
    {"O", "Public administration and defence", 84, 84},
    {"P", "Education", 85, 85},
    {"Q", "Human health and social work activities", 86, 88},
    {"R", "Arts, entertainment and recreation", 90, 93},
    {"S", "Other service activities", 94, 96},
    {"T", "Activities of households as employers", 97, 98},
    {"U", "Activities of extraterritorial organisations", 99, 99}
  ]

  def sections do
    @sections
    |> Enum.filter(fn {_l, _t, lo, hi} ->
      Enum.any?(Map.keys(@divisions), &in_range?(&1, lo, hi))
    end)
    |> Enum.map(fn {l, t, _lo, _hi} -> {l, t} end)
  end

  def divisions_for_section(letter) do
    case Enum.find(@sections, fn {l, _, _, _} -> l == letter end) do
      {_, _, lo, hi} ->
        @divisions
        |> Enum.filter(fn {code, _} -> in_range?(code, lo, hi) end)
        |> Enum.map(fn {code, {en, _}} -> {code, en} end)
        |> Enum.sort()

      nil ->
        []
    end
  end

  def groups_for_division(div2) do
    @groups
    |> Enum.filter(fn {code, _} -> String.starts_with?(code, div2) end)
    |> Enum.map(fn {code, {en, _}} -> {code, en} end)
    |> Enum.sort()
  end

  def classes_for_group(grp3) do
    @classes
    |> Enum.filter(fn {code, _} -> String.starts_with?(code, grp3) end)
    |> Enum.map(fn {code, {en, _}} -> {code, en} end)
    |> Enum.sort()
  end

  # All 4-digit classes under a node id (section letter or 2/3/4-digit code).
  def leaf_classes(id) do
    cond do
      section?(id) ->
        {_, _, lo, hi} = Enum.find(@sections, fn {l, _, _, _} -> l == id end)
        @classes |> Map.keys() |> Enum.filter(&in_range?(String.slice(&1, 0, 2), lo, hi))

      true ->
        @classes |> Map.keys() |> Enum.filter(&String.starts_with?(&1, id))
    end
  end

  def expand_codes(ids) when is_list(ids),
    do: ids |> Enum.flat_map(&leaf_classes/1) |> Enum.uniq()

  def node_label(id), do: if(section?(id), do: section_title(id), else: label(id) || id)

  # Whether selecting `a` covers `d` (a is ancestor-or-equal of d).
  def contains?(a, d) do
    cond do
      section?(a) and section?(d) -> a == d
      section?(a) -> section_of(d) == a
      section?(d) -> false
      true -> String.starts_with?(d, a)
    end
  end

  def section_of(code) when is_binary(code) do
    d = String.slice(code, 0, 2)

    case Enum.find(@sections, fn {_l, _t, lo, hi} -> in_range?(d, lo, hi) end) do
      {l, _, _, _} -> l
      nil -> nil
    end
  end

  defp section_title(letter) do
    case Enum.find(@sections, fn {l, _, _, _} -> l == letter end) do
      {_, t, _, _} -> t
      nil -> letter
    end
  end

  defp section?(id), do: String.match?(id, ~r/^[A-U]$/)

  defp in_range?(code2, lo, hi) do
    case Integer.parse(code2) do
      {n, _} -> n >= lo and n <= hi
      :error -> false
    end
  end
end
