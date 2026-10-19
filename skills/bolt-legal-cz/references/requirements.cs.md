# Guidelines: povinné údaje a informace na webu podnikatele v ČR

19. 10. 2026

> Referenční zadání skillu `bolt-legal-cz`. ID požadavků (OP-, ID-, SP-, EC-, REG-, WB-, AG-) používá `SKILL.md`, šablony i `scripts/verify.sh`. Data jsou v Bolt CMS uložena v `theme.yaml` (sekce `contact:` a `legal:`, viz `examples/theme.legal.yaml`). Zásady ochrany osobních údajů a cookie lišta jsou v samostatném skillu `bolt-cookie-consent`.

## Účel a jak dokument číst

Dokument říká, co musí web podnikatele v ČR obsahovat podle toho, **kdo ho provozuje** a **co na něm dělá** (prodává spotřebitelům, uzavírá smlouvy online, zveřejňuje recenze …). Vychází z právních předpisů účinných ke dni 19. 10. 2026 a z jednoho přijatého předpisu s pozdější účinností (EC-05). Nejde o právní stanovisko; fakta o podnikateli potvrzuje provozovatel webu, obsah obchodních podmínek posuzuje právník.

- **MUSÍ** = požadavek z právního předpisu. Porušení = riziko sankce.
- **MĚL BY** = dobrá praxe nebo výklad, který zákon výslovně neukládá. Odchylku agent zdůvodní.
- **NESMÍ** = postup, který předpis zakazuje nebo který klame spotřebitele.

## Krok 0: kdo web provozuje (OP)

Všechno další se odvíjí od odpovědi na první otázku. Agent ji položí vždy, i když odpověď „OSVČ – živnostník“ je nejčastější (AG-01).

| ID | Provozovatel | `legal.operator` | Zápis podle § 435 OZ |
| --- | --- | --- | --- |
| OP-01 | **Fyzická osoba podnikající podle živnostenského zákona** (OSVČ – živnostník) | `trade` | živnostenský rejstřík = „jiná evidence“ |
| OP-02 | **Obchodní korporace nebo jiná osoba zapsaná v obchodním rejstříku** (s.r.o., a.s., v.o.s., k.s., družstvo; i živnostník zapsaný do OR dobrovolně) | `company` | obchodní rejstřík: soud, oddíl, vložka |
| OP-03 | **Svobodné povolání nebo jiné oprávnění mimo živnostenský zákon** (advokát, lékař, architekt, daňový poradce, auditor, notář, exekutor …) | `profession` | seznam nebo evidence komory či úřadu |
| OP-04 | **Nepodnikatel** (spolek bez podnikání, soukromá osoba, veřejný subjekt) | `other` | § 435 OZ se nepoužije; pro web veřejného subjektu platí jiné předpisy (zákon č. 99/2019 Sb.), mimo rozsah skillu |

Spolek, nadace nebo ústav, který podniká (vedlejší hospodářská činnost), je podnikatel → `other` s textem zápisu ve spolkovém / nadačním rejstříku (ID-04).

Druhá otázka: **prodává provozovatel výrobky nebo služby spotřebitelům** (lidem mimo jejich podnikání)? Kadeřnice, instalatér, fotograf, autoservis, lektor – ano. Čistě B2B (účetní služby jen firmám, velkoobchod) – ne. Odpověď zapíná sekci SP.

Třetí otázka: **uzavírá se smlouva přímo na webu** (košík, objednávkový formulář s platbou, rezervace s platbou, předplatné)? Zapíná sekci EC. Poptávkový formulář, po kterém následuje individuální nabídka, smlouvu na webu neuzavírá.

## Identifikace podnikatele (ID)

Základ je [§ 435 odst. 1 občanského zákoníku](https://www.podnikatel.cz/zakony/novy-obcansky-zakonik/zneni-20230106/f4580257/):

> „Každý podnikatel musí uvádět na obchodních listinách a v rámci informací zpřístupňovaných veřejnosti prostřednictvím dálkového přístupu své jméno a sídlo. Podnikatel zapsaný v obchodním rejstříku uvede na obchodní listině též údaj o tomto zápisu včetně oddílu a vložky; podnikatel zapsaný v jiném veřejném rejstříku uvede údaj o svém zápisu do tohoto rejstříku; podnikatel nezapsaný ve veřejném rejstříku uvede údaj o svém zápisu do jiné evidence. Byl-li podnikateli přidělen identifikující údaj, uvede i ten.“

Odstavec 2: další údaje lze uvést, „nejsou-li způsobilé vyvolat klamavý dojem“.

| ID | Požadavek | Síla | Pramen |
| --- | --- | --- | --- |
| ID-01 | **Jméno**: u fyzické osoby jméno a příjmení (případně s dodatkem, např. „Jan Novák – Truhlářství“), u právnické osoby firma včetně právní formy („Example s.r.o.“), přesně jako v rejstříku. | MUSÍ | § 435/1 OZ |
| ID-02 | **Sídlo**: adresa zapsaná v rejstříku (u živnostníka sídlo podle živnostenského rejstříku, ne provozovna). Provozovnu nebo kontaktní adresu lze uvést navíc, ale jako takovou označenou. | MUSÍ | § 435/1 OZ |
| ID-03 | **IČO** (identifikující údaj), 8 číslic s platným kontrolním součtem. | MUSÍ | § 435/1 OZ |
| ID-04 | **Údaj o zápisu**: živnostník „zapsaný v živnostenském rejstříku“ (lze doplnit živnostenský úřad); obchodní rejstřík: soud, oddíl, vložka („Zapsáno v obchodním rejstříku: Městský soud v Praze, oddíl C, vložka 12345“); svobodné povolání: evidence komory s číslem zápisu; spolek, nadace, ústav: příslušný veřejný rejstřík se spisovou značkou. | MUSÍ | § 435/1 OZ; u obchodních korporací též [§ 7 ZOK](https://portal.pohoda.cz/zakon-a-pravo/novy-obcansky-zakonik/novy-obcansky-zakonik-obchodni-listiny) |
| ID-05 | Údaje ID-01 až ID-04 jsou **na každé stránce** (patička) jako **text**, ne obrázek. Zákon místo neurčuje; patička je jediné místo, které návštěvník najde vždy, a text přečte i čtečka. | MĚL BY | konvence skillu |
| ID-06 | Údaje **odpovídají rejstříku** ([ARES](https://ares.gov.cz)). Stará adresa sídla nebo dřívější firma je nepravdivý údaj. | MUSÍ | § 435 OZ |
| ID-07 | **DIČ**: zákon ho na webu nevyžaduje (povinné je na daňových dokladech). Plátce DPH ho uvede, protože ho zákazníci potřebují. Údaj „neplátce DPH“ povinný není. | MĚL BY | – |
| ID-08 | **Základní kapitál**, pokud je uveden, jen ve výši upsané a splacené části. | MUSÍ | § 7 ZOK |
| ID-09 | **Nic klamavého**: OSVČ se neoznačuje „s.r.o.“ ani „firma XY a.s.“, neuvádí se zaniklý zápis, cizí IČO (např. původního majitele šablony webu) nebo neplatná adresa. | NESMÍ | § 435/2 OZ |

Kontrolu u živnostníků provádí živnostenský úřad, u zapsaných v obchodním rejstříku rejstříkový soud.

## Spotřebitelé (SP)

Platí pro každého **prodávajícího** podle zákona č. 634/1992 Sb., o ochraně spotřebitele (ZOS) – tedy i pro poskytovatele služeb spotřebitelům, nejen pro e-shopy. Znění podle [ZOS ve znění účinném od 20. 8. 2025](https://www.zakonyprolidi.cz/cs/1992-634).

| ID | Požadavek | Síla | Pramen |
| --- | --- | --- | --- |
| SP-01 | **Mimosoudní řešení spotřebitelských sporů (ADR)** na webu: věcně příslušný subjekt a jeho **internetová adresa** (viditelně, ne jen jako odkaz pod názvem). Obecně Česká obchodní inspekce ([coi.gov.cz](https://coi.gov.cz/informace-o-adr/)); energetika ERÚ, elektronické komunikace a poštovní služby ČTÚ, finanční služby finanční arbitr, právní služby advokátů ČAK. Odkazuje-li smlouva na obchodní podmínky, patří informace i do nich. | MUSÍ | § 14/1 ZOS; pokuta až 1 000 000 Kč (§ 24/5 m), § 24/22 b) |
| SP-02 | **Odkaz na evropskou platformu ODR** (`ec.europa.eu/consumers/odr`) odstranit: platforma byla 20. 7. 2025 zrušena nařízením (EU) 2024/3228 a odkaz spotřebitele klame. | NESMÍ | [nařízení (EU) 2024/3228](https://legalblogs.wolterskluwer.com/mediation-blog/end-of-an-era-from-clicks-to-complaints-what-the-eu-odr-platforms-closure-means-for-businesses-and-consumers/) |
| SP-03 | **Reklamace**: informace „o rozsahu, podmínkách a způsobu uplatnění práva z vadného plnění, spolu s údaji o tom, kde lze reklamaci uplatnit“. U e-shopu stránka *Reklamační řád*; u služeb stačí oddíl v obchodních podmínkách nebo na stránce kontaktů. | MUSÍ (informovat); MĚL BY (na webu) | § 13/1 ZOS; pokuta až 1 000 000 Kč |
| SP-04 | **Ceny pro spotřebitele** jako konečné ceny včetně DPH a všech poplatků. Ceník „bez DPH“ je přípustný jen pro podnikatele a musí tak být zřetelně označen; spotřebiteli se nikdy neukazuje jen cena bez DPH. | MUSÍ | § 12 ZOS + cenové předpisy (zákon č. 526/1990 Sb.); pokuta až 5 000 000 Kč |
| SP-05 | **Slevy**: oznámení o slevě uvádí nejnižší cenu, za kterou prodávající výrobek nabízel v posledních 30 dnech před slevou. | MUSÍ | § 12a ZOS; pokuta až 5 000 000 Kč |
| SP-06 | **Recenze a reference**: zpřístupňuje-li web hodnocení od jiných spotřebitelů (hvězdičky, citace klientů, reference), uvede, **zda a jak** zajišťuje, že pocházejí od lidí, kteří službu nebo výrobek skutečně využili. Neověřuje-li je, řekne to. Smyšlené nebo upravené recenze jsou nekalá obchodní praktika. | MUSÍ | § 5a/5 ZOS |
| SP-07 | **Čeština**: písemné informace pro spotřebitele (SP-01, SP-03, obchodní podmínky) jsou v češtině. Vícejazyčný web je má v české verzi vždy. | MUSÍ | § 11/1 ZOS |

## Smlouvy uzavírané na webu (EC)

Platí, když se smlouva se spotřebitelem uzavírá přímo na webu (distanční smlouva přes on-line rozhraní).

| ID | Požadavek | Síla | Pramen |
| --- | --- | --- | --- |
| EC-01 | **Předsmluvní informace** před odesláním objednávky: identita a kontakt podnikatele včetně e-mailu a telefonu, hlavní vlastnosti plnění, celková cena, platba, dodání, náklady na dopravu, reklamace (SP-03), odstoupení (EC-04), ADR (SP-01). Obvykle stránka *Obchodní podmínky* + rekapitulace v objednávce. | MUSÍ | § 1811, § 1820 OZ |
| EC-02 | **Obchodní podmínky** jako samostatná stránka dostupná z patičky a z objednávky; obsahují SP-01 a informace o přístupnosti (EC-06), pokud se na podnikatele vztahuje. | MĚL BY (stránka); MUSÍ (obsah) | § 1820 OZ, § 14/1 ZOS |
| EC-03 | **Tlačítko objednávky** označené „Objednávka zavazující k platbě“ nebo jinou jednoznačnou formulací. „Odeslat“ nebo „Pokračovat“ nestačí. | MUSÍ | § 1826a/2 OZ |
| EC-04 | **Odstoupení do 14 dnů**: podmínky, lhůta, postup a vzorový formulář (náležitosti stanoví nařízení vlády); výjimky podle § 1837 OZ (např. zboží na míru, služba plně poskytnutá se souhlasem). | MUSÍ | § 1820/1 i), § 1829 OZ |
| EC-05 | **Tlačítko pro odstoupení od smlouvy** – nový [§ 1830a OZ](https://www.zakonyprolidi.cz/cs/2026-159) ze zákona č. 159/2026 Sb., **účinnost od 1. 1. 2027**. Výrazné, snadno přístupné, dostupné po celou lhůtu pro odstoupení, s nápisem „Odstoupit od smlouvy“ (nebo jinou jednoznačnou formulací); formulář, kde spotřebitel vyplní nebo potvrdí jméno, údaje o smlouvě a e-mail pro potvrzení; druhé tlačítko „Potvrdit odstoupení od smlouvy“; potvrzení přijetí v textové podobě bez zbytečného odkladu, s obsahem a datem a časem odeslání. Předsmluvní informace (§ 1820/1 i) nově zmiňují možnost odstoupit tlačítkem a kde je. Před 1. 1. 2027 je to příprava (varování), od 1. 1. 2027 požadavek. | MUSÍ od 1. 1. 2027 | § 1830a OZ, § 1820/1 i) OZ ve znění zákona č. 159/2026 Sb. |
| EC-06 | **Přístupnost služeb elektronického obchodu** (Evropský akt o přístupnosti, zákon č. 424/2023 Sb., od 28. 6. 2025): web přístupný podle harmonizovaných norem (WCAG 2.1 AA) a informace o přístupnosti v obchodních podmínkách. **Neplatí pro mikropodnik** poskytující služby (méně než 10 zaměstnanců a roční obrat nebo bilanční suma do 2 mil. EUR) – většina živnostníků. Dozor ČOI. | MUSÍ (mimo mikropodniky) | [zákon č. 424/2023 Sb.](https://www.epravo.cz/top/clanky/zakon-o-pristupnosti-120042.html), [ČOI](https://portal.gov.cz/sluzby-vs/informovani-ceske-obchodni-inspekce-o-neplneni-pozadavku-na-pristupnost-S93683) |

## Zvláštní případy

| ID | Požadavek | Síla | Pramen |
| --- | --- | --- | --- |
| REG-01 | **Regulované povolání** (OP-03): profesní komora nebo dozorový úřad, profesní titul a stát, kde byl udělen, odkaz na profesní předpisy (např. ČAK – advokátní předpisy). Česká úprava čl. 5 směrnice o elektronickém obchodu není jednoznačná, proto MĚL BY; u spotřebitelů je komora často i subjektem ADR (SP-01). | MĚL BY | čl. 5 směrnice 2000/31/ES |
| WB-01 | **Whistleblowing**: povinný subjekt zveřejní „způsobem umožňujícím dálkový přístup“ (prakticky stránka na webu) způsoby podání oznámení vnitřním systémem i ministerstvu, příslušnou osobu s telefonem a e-mailem (nebo jinou adresou pro doručování) a zda vylučuje oznámení od osob, které pro něj nepracují. Povinný subjekt je mj. zaměstnavatel s nejméně 50 zaměstnanci a **povinná osoba podle AML zákona bez ohledu na počet zaměstnanců** (např. realitní zprostředkovatel; účetní a daňové služby, auditor – ověřit podle § 2 zákona č. 253/2008 Sb.). | MUSÍ (povinné subjekty) | [§ 8/1, § 9/2 b) zákona č. 171/2023 Sb.](https://www.zakonyprolidi.cz/cs/2023-171), § 21/6 b) zákona č. 253/2008 Sb. |
| NL-01 | **Newsletter / obchodní sdělení e-mailem**: jen se souhlasem (nezaškrtnuté políčko) nebo vlastním zákazníkům; každé sdělení s možností odhlášení. Formulář řeší `bolt-cookie-consent` (`_privacy-form-note.twig`). | MUSÍ | § 7 zákona č. 480/2004 Sb. |
| GDPR-01 | **Zásady ochrany osobních údajů** odkazované z patičky každé stránky a **cookie lišta** při netechnických cookies. | MUSÍ | GDPR čl. 13; § 89/3 ZEK – skill `bolt-cookie-consent` |

## Mimo rozsah

- Obsah obchodních podmínek, reklamačního řádu a smluv – skill hlídá jejich existenci a povinné prvky, ne právní kvalitu (AG-03).
- Online platformy a tržiště, obsah vkládaný uživateli (nařízení DSA), weby veřejné správy (zákon č. 99/2019 Sb.), regulované finanční služby, prodej alkoholu, tabáku a léčiv (věkové a licenční požadavky), licence k fotografiím a písmům.

## Datový model

Jediný zdroj pravdy je `theme.yaml` (vzor `examples/theme.legal.yaml`):

- `contact:` – `name` (ID-01), `address` (ID-02 – sídlo), `ico` (ID-03), `email`, `phone`; sdílí ho patička, kontakty, stránka zásad (`bolt-cookie-consent` z něj předvyplní prvního správce) a `llms.txt`.
- `legal:` – `operator` (OP), `registry` (ID-04), `dic` (ID-07), `consumers` (SP), `adr` (SP-01), `online_contracts` (EC), `reviews` (SP-06), `regulated` (REG-01), `whistleblowing_url` (WB-01), `microenterprise` (EC-06).

Šablony ani překlady tato fakta neopakují. Překladové katalogy (`legal.*`) obsahují jen pevné formulace („IČO“, „Zapsáno v obchodním rejstříku: …“).

## Akceptační checklist

- [ ] OP: provozovatel a profil (spotřebitelé, smlouvy online, recenze) potvrzen s provozovatelem a zapsán v `AGENTS.md`.
- [ ] ID-01–ID-04 na každé stránce v patičce jako text; shoda s ARES (ID-06).
- [ ] ID-07: plátce DPH uvádí DIČ; ID-08 a ID-09: nic klamavého ani zastaralého.
- [ ] SP-01: subjekt ADR s viditelnou internetovou adresou (spotřebitelé); SP-02: žádný odkaz na platformu ODR nikde na webu ani v obchodních podmínkách.
- [ ] SP-03: kde a jak reklamovat; SP-04: ceny pro spotřebitele s DPH; SP-05: slevy s nejnižší cenou za 30 dní.
- [ ] SP-06: u recenzí a referencí věta o ověřování.
- [ ] SP-07: spotřebitelské informace česky.
- [ ] EC-01–EC-04 (smlouvy online): obchodní podmínky, tlačítko „Objednávka zavazující k platbě“, poučení o odstoupení se vzorovým formulářem.
- [ ] EC-05: tlačítko „Odstoupit od smlouvy“ s potvrzením – nejpozději 1. 1. 2027.
- [ ] EC-06: přístupnost, nebo zdokumentovaná výjimka mikropodniku.
- [ ] REG-01, WB-01, NL-01 podle profilu; GDPR-01 přes `bolt-cookie-consent`.

## Pravidla pro agenta (AG)

| ID | Pravidlo |
| --- | --- |
| AG-01 | Nejdřív se zeptej, kdo web provozuje (OP). Nabídni „OSVČ – živnostník“ jako první možnost, ale odpověď nikdy nedomýšlej. |
| AG-02 | Jméno, sídlo, IČO, zápis a DIČ ber z ARES nebo od provozovatele. Co chybí, zůstane `[DOPLNIT …]` a jde na seznam otázek pro provozovatele. |
| AG-03 | Nejde o právní stanovisko. Obchodní podmínky, reklamační řád a regulované činnosti doporuč nechat zkontrolovat advokátem. |
| AG-04 | Jeden zdroj pravdy: fakta jen v `theme.yaml`. Pokud web používá `bolt-cookie-consent`, první správce v `privacy.controllers` musí mít stejné jméno, sídlo a IČO jako `contact:`. |
| AG-05 | Před předáním spusť ověření proti ARES (`verify.sh --ares`) a živou kontrolu webu (`check-site.php`). |
| AG-06 | Data účinnosti hlídej: dokument odpovídá stavu k datu v záhlaví. Před 1. 1. 2027 upozorni provozovatele e-shopu na EC-05. |

## Zdroje

**Předpisy**

- [Zákon č. 89/2012 Sb., občanský zákoník – § 435](https://www.podnikatel.cz/zakony/novy-obcansky-zakonik/zneni-20230106/f4580257/)
- [Zákon č. 634/1992 Sb., o ochraně spotřebitele – znění od 20. 8. 2025](https://www.zakonyprolidi.cz/cs/1992-634)
- [Zákon č. 159/2026 Sb. (tlačítko pro odstoupení, § 1830a OZ, účinnost 1. 1. 2027)](https://www.zakonyprolidi.cz/cs/2026-159)
- [Zákon č. 171/2023 Sb., o ochraně oznamovatelů](https://www.zakonyprolidi.cz/cs/2023-171)
- [Zákon č. 424/2023 Sb., o požadavcích na přístupnost (epravo.cz)](https://www.epravo.cz/top/clanky/zakon-o-pristupnosti-120042.html)
- [ARES – REST API ekonomických subjektů](https://ares.gov.cz/ekonomicke-subjekty-v-be/rest)

**Úřady**

- [ČOI – informace o ADR](https://coi.gov.cz/informace-o-adr/)
- [ČOI – nedodržení požadavků na přístupnost](https://portal.gov.cz/sluzby-vs/informovani-ceske-obchodni-inspekce-o-neplneni-pozadavku-na-pristupnost-S93683)
- [ERÚ – rozhodnutí o pokutě za chybějící informaci o ADR na webu](https://eru.gov.cz/sites/default/files/obsah/prilohy/r36423.pdf)

**Články**

- [epravo.cz – Novinka v ZOS: mimosoudní řešení spotřebitelských sporů](https://www.epravo.cz/top/clanky/novinka-v-zakone-o-ochrane-spotrebitele-mimosoudni-reseni-spotrebitelskych-sporu-100463.html)
- [BusinessInfo – povinnosti podnikatelů v ADR](https://www.businessinfo.cz/clanky/povinnosti-podnikatelu-v-ramci-mimosoudniho-reseni-spotrebitelskych-sporu/)
- [Právní prostor – tlačítková novela](https://www.pravniprostor.cz/clanky/obcanske-pravo/od-objednavky-k-odstoupeni-tlacitkova-novela-jako-dalsi-krok-k-realne-ochrane-spotrebitele)
- [Wolters Kluwer – konec platformy ODR](https://legalblogs.wolterskluwer.com/mediation-blog/end-of-an-era-from-clicks-to-complaints-what-the-eu-odr-platforms-closure-means-for-businesses-and-consumers/)
- [epravo.cz – novelizace ochrany spotřebitele (slevy, recenze)](https://epravo.cz/top/clanky/novelizace-upravy-v-oblasti-prava-ochrany-spotrebitele-115281.html)
- [epravo.cz – whistleblowing u realitních zprostředkovatelů](https://www.epravo.cz/top/clanky/nove-povinnosti-pro-realitni-zprostredkovatele-a-developery-v-kontextu-whistleblowingu-116866.html)
- [epravo.cz – internetové stránky s.r.o.](https://www.epravo.cz/top/clanky/nekolik-poznamek-k-internetovym-strankam-spolecnosti-s-rucenim-omezenym-100295.html)
- [ARROWS – povinné informace na webu](https://arws.cz/novinky-v-arrows/jake-informace-musi-realitni-kancelar-nebo-realitni-makler-zverejnit-na-webu)
