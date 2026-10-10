# Guidelines: cookie lišta a Zásady ochrany osobních údajů

Oct 10, 2026 · @Tomas

> Referenční zadání skillu `bolt-cookie-consent`. ID požadavků (INV-, CB-, DP-, PP-, VAR-, DM-, AG-) používá `SKILL.md`, šablony i `scripts/verify.sh`. Datový model z této kapitoly je v Bolt CMS uložen v `theme.yaml` (sekce `analytics:` a `privacy:`, viz `examples/theme.privacy.yaml`).

## Účel a jak dokument číst

Dokument je zadání pro agenta, který navrhuje a implementuje cookie lištu a stránku Zásady ochrany osobních údajů pro české weby jednoho nebo více podnikatelů. Vychází z platné legislativy a praxe Úřadu pro ochranu osobních údajů (ÚOOÚ) ke dni 10. 10. 2026. Nejde o právní stanovisko; obsah stránky (účely, právní základy, doby uložení) musí potvrdit provozovatel webu.

- **MUSÍ** = požadavek z právního předpisu nebo z výslovného stanoviska ÚOOÚ / SDEU. Porušení = riziko sankce.
- **MĚL BY** = dobrá praxe dozorových úřadů (EDPB, ÚOOÚ). Odchylku agent zdůvodní.
- **NESMÍ** = postup, který ÚOOÚ nebo EDPB výslovně označil za protiprávní.
- Každý požadavek má ID (např. CB-03), na které odkazuje akceptační checklist.

## Právní rámec

Od 1. 1. 2022 platí v ČR pro cookies režim opt-in: netechnické cookies smí web uložit až po předchozím prokazatelném souhlasu (§ 89 odst. 3 zákona č. 127/2005 Sb., novela č. 374/2021 Sb.). Zpracování údajů získaných přes cookies se navíc řídí GDPR, protože cookie je síťový identifikátor (recitál 30).

| Pramen | Co z něj plyne pro design |
| --- | --- |
| [§ 89 odst. 3 ZEK](https://uoou.gov.cz/media/poskytnute-informace/2025/1292025/prikaz-cj-uoou-0248222-9.pdf) | Souhlas předem; bez souhlasu jen technické ukládání pro přenos zprávy nebo službu výslovně vyžádanou uživatelem. |
| GDPR čl. 4 bod 11, čl. 7 | Souhlas svobodný, konkrétní, informovaný, jednoznačný; odvolání stejně snadné jako udělení. |
| GDPR čl. 12–14 | Obsah a forma informací na stránce Zásad (stručně, srozumitelně, snadno dostupně). |
| GDPR čl. 21 odst. 4 | Právo vznést námitku uvést výslovně a odděleně od ostatních informací. |
| GDPR čl. 26 | Společní správci: ujednání + zveřejnit jeho podstatu; práva lze uplatnit u každého správce. |
| [ÚOOÚ – Q&A Cookies](https://uoou.gov.cz/verejnost/qa-otazky-a-odpovedi/cookies) | Závazná praxe dozoru: tlačítka, vrstvy, zavření lišty, doby platnosti souhlasu. |
| [ÚOOÚ – leták k cookie liště](https://uoou.gov.cz/media/publikace/letaky-gdpr/3-letak-web.pdf) | Shrnutí téhož ve formě FAQ. |
| SDEU C-673/17 Planet49 | Předem zaškrtnutá políčka nejsou souhlas. |
| [SDEU C-40/17 Fashion ID](https://advokatnidenik.cz/2019/07/30/soudni-dvur-eu-k-odpovednosti-provozovatele-internetovych-stranek-a-prenos-dat-facebooku/) | Provozovatel webu s pluginem třetí strany je společným správcem pro sběr a předání dat. |
| [EDPB Cookie Banner Taskforce (01/2023)](https://www.insideprivacy.com/eu-data-protection/edpb-publishes-report-of-cookie-banners-taskforce/) | Odmítnutí v 1. vrstvě, žádný odkaz místo tlačítka, žádné klamavé barvy a kontrast. |
| [EDPB Guidelines 2/2023](https://hunton.com/privacy-and-information-security-law/edpb-publishes-guidelines-to-clarify-scope-of-eu-cookie-notice-and-consent-requirements) | Pravidla platí i pro pixely, tracking odkazy, fingerprinting, localStorage. |
| [EDPB Guidelines 03/2022](https://www.edpb.europa.eu/our-work-tools/our-documents/guidelines/guidelines-032022-deceptive-design-patterns-social-media_en) | Katalog zakázaných „deceptive design patterns“. |
| [§ 435 obč. zákoníku](https://www.podnikatel.cz/zakony/novy-obcansky-zakonik/zneni-20230106/f4580257/) | Na webu podnikatele jméno, sídlo, IČO a údaj o zápisu do rejstříku / evidence. |
| [Zákon č. 424/2023 Sb.](https://www.epravo.cz/top/clanky/zakon-o-pristupnosti-120042.html) | Od 28. 6. 2025 přístupnost e-commerce služeb; mikropodniky mají výjimku. |

Vymáhání je reálné: ÚOOÚ v roce 2023 uložil pokutu 602 000 Kč za analytickou cookie nastavenou před volbou v liště, cookies bez uvedeného účelu (kategorie „neklasifikované“) a popisy cookies jen v angličtině; chybějící „Odmítnout“ v 1. vrstvě úřad vytkl už v předchozím upozornění ([příkaz UOOU-02482/22-9](https://uoou.gov.cz/media/poskytnute-informace/2025/1292025/prikaz-cj-uoou-0248222-9.pdf)).

## Krok 0: inventura a rozhodnutí, zda je lišta potřeba

Cookie lišta je potřeba jen tehdy, když web používá aspoň jednu netechnickou technologii. Stránku Zásad ochrany osobních údajů potřebuje každý web, který zpracovává osobní údaje – i čistě technickými cookies nebo kontaktním formulářem ([ÚOOÚ](https://uoou.gov.cz/verejnost/qa-otazky-a-odpovedi/cookies)).

**INV-01 (MUSÍ)** Před návrhem agent sestaví inventář všeho, co web ukládá do zařízení nebo z něj čte, a všech požadavků na třetí strany: cookies, localStorage, sessionStorage, IndexedDB, pixely, tracking odkazy, fingerprinting, vložené iframy (YouTube, Mapy, Facebook), externí fonty a CDN. Pravidla souhlasu se vztahují i na technologie podobné cookies a fingerprinting ([ÚOOÚ](https://uoou.gov.cz/verejnost/qa-otazky-a-odpovedi/cookies), [EDPB 2/2023](https://hunton.com/privacy-and-information-security-law/edpb-publishes-guidelines-to-clarify-scope-of-eu-cookie-notice-and-consent-requirements)).

**INV-02 (MUSÍ)** Každou položku zařadí do kategorie podle účelu:

| Kategorie | Souhlas | Příklady |
| --- | --- | --- |
| Nezbytné (technické) | Ne | session, košík, CSRF token, uložení volby v cookie liště, load balancer |
| Preferenční / funkční | Ano | zapamatování jazyka nebo regionu, pokud ho uživatel výslovně nevyžádal |
| Analytické | Ano | Google Analytics, Matomo s cookies, Hotjar, Microsoft Clarity |
| Marketingové | Ano | Meta Pixel, Google Ads, Sklik retargeting, LinkedIn Insight |
| Obsah třetích stran | Ano | vložené video, mapa, sociální plugin (provozovatel webu je pro sběr a předání dat společným správcem – Fashion ID) |

**INV-03 (NESMÍ)** Kategorie „neklasifikované“ nebo položka bez účelu. Každá položka musí mít účel v češtině.

**INV-04 (MUSÍ)** Analytika první strany s cookies vyžaduje souhlas k uložení cookie podle ZEK. Oprávněný zájem může být právním základem jen pro následné zpracování dat; bez souhlasu se cookie nesmí uložit vůbec.

**Rozhodnutí:** jen nezbytné položky → žádná lišta, jen odkaz na Zásady v patičce. Aspoň jedna souhlasová položka → lišta podle sekce níže.

## Cookie lišta

Lišta má dvě vrstvy a jednu trvalou vstupní bránu v patičce. První vrstva nabízí „Přijmout vše“ a „Odmítnout vše“ vedle sebe ve srovnatelném provedení; druhá vrstva umožní volbu po kategoriích.

### Chování před volbou

- **CB-01 (MUSÍ)** Do udělení souhlasu se nenačte žádný netechnický skript, pixel, iframe ani cookie. Platí i pro uživatele, který lištu zavřel nebo na ni nereagoval ([ÚOOÚ](https://uoou.gov.cz/verejnost/qa-otazky-a-odpovedi/cookies)).
- **CB-02 (MUSÍ)** Vložený obsah třetích stran (video, mapa) se před souhlasem zobrazí jako zástupný blok s textem, co se načte a kdo je poskytovatel, a tlačítkem pro načtení po souhlasu s danou kategorií.
- **CB-03 (MUSÍ)** Lišta nesmí bránit v používání webu, ani když uživatel ještě nevolil. Žádná cookie wall (přístup podmíněný souhlasem) ([ÚOOÚ](https://uoou.gov.cz/verejnost/qa-otazky-a-odpovedi/cookies)).
- **CB-04 (MĚL BY)** Neblokující lišta u spodního okraje. Je-li uprostřed obrazovky (modál), MUSÍ mít prvek pro zavření bez volby; zavření = nesouhlas, netechnické položky zůstanou vypnuté.
- **CB-05 (NESMÍ)** Text typu „Používáním webu souhlasíte s cookies“. ÚOOÚ takové lišty opakovaně označil za nezákonné ([UOOU-00747/23](https://uoou.gov.cz/media/poskytnute-informace/2024/1742024-1/79-cj-uoou-0074723-4-dokument-c-79.pdf)).

### První vrstva

- **CB-10 (MUSÍ)** Tlačítka „Přijmout vše“ a „Odmítnout vše“ ve stejné vrstvě. ÚOOÚ uvádí jako dobrou praxi obě v první vrstvě na roveň ve srovnatelném vizuálním provedení; EDPB taskforce: většina dozorových úřadů požaduje odmítnutí v první vrstvě ([EDPB](https://hunton.com/privacy-and-information-security-law/edpb-publishes-report-of-outcome-of-the-cookie-banner-taskforce)). Agent je umístí vždy obě do první vrstvy.
- **CB-11 (MUSÍ)** Odmítnutí je tlačítko, ne textový odkaz.
- **CB-12 (MUSÍ)** „Přijmout“ nesmí být výrazně větší ani barevně výraznější než „Odmítnout“; stejná velikost, font, padding a typ prvku. Kontrast textu obou tlačítek ≥ 4,5 : 1 (WCAG). Barvy nesmí obracet obvyklý význam (např. odmítnutí červeně) ([ÚOOÚ](https://uoou.gov.cz/verejnost/qa-otazky-a-odpovedi/cookies)).
- **CB-13 (MUSÍ)** Třetí prvek „Nastavení“ otevře druhou vrstvu.
- **CB-14 (MUSÍ)** Krátký text v češtině uvede: kdo je správce (jméno / obchodní firma; u více správců všechny), k jakým účelům cookies slouží (kategorie), že se data předávají třetím stranám (jmenovitě nebo s odkazem na seznam), že souhlas lze kdykoli odvolat a kde. Odkaz na Zásady a na seznam cookies.
- **CB-15 (MUSÍ)** Na mobilu (šířka 360 px) jsou obě hlavní tlačítka vidět bez scrollování v liště.

### Druhá vrstva (Nastavení)

- **CB-20 (MUSÍ)** Přepínač pro každou souhlasovou kategorii, výchozí stav vypnuto (Planet49). „Nezbytné“ zobrazit jako zapnuté a neměnné, s vysvětlením proč.
- **CB-21 (MUSÍ)** U každé kategorie popis účelu a rozbalitelný seznam položek: název, poskytovatel, účel, doba platnosti, první/třetí strana, předání mimo EU/EHP.
- **CB-22 (MUSÍ)** Tlačítka „Uložit výběr“, „Přijmout vše“, „Odmítnout vše“.
- **CB-23 (MUSÍ)** Veškeré texty a popisy cookies v češtině; anglické popisy od poskytovatelů nestačí (důvod pokuty v příkazu UOOU-02482/22-9).
- **CB-24 (MUSÍ)** Doba platnosti každé cookie přiměřená účelu; roky bez zdůvodnění porušují zásadu omezení uložení.

### Odvolání a změna volby

- **CB-30 (MUSÍ)** Odkaz „Nastavení cookies“ v patičce každé stránky, otevře druhou vrstvu s aktuálním stavem. Odvolání musí být stejně snadné jako udělení.
- **CB-31 (MUSÍ)** Po odvolání souhlasu skripty přestanou běžet a cookies dané kategorie se smažou (u cookies první strany).

### Uložení volby a opakované zobrazení

- **CB-40 (MUSÍ)** Volbu uložit v nezbytné cookie / localStorage: kategorie, verze konfigurace, časové razítko. Správce musí umět souhlas prokázat.
- **CB-41 (MĚL BY)** Platnost souhlasu 12 měsíců. Po odmítnutí lištu znovu nezobrazovat aspoň 6 měsíců ([ÚOOÚ](https://uoou.gov.cz/verejnost/qa-otazky-a-odpovedi/cookies)).
- **CB-42 (MUSÍ)** Při významné změně (nové účely, noví správci, přenos mimo EU) zvýšit verzi konfigurace a požádat znovu i ty, kdo souhlasili. Výměna jednotlivé cookie se stejným účelem a správcem za významnou změnu nepovažuje.
- **CB-43 (NESMÍ)** Souhlas odvozený z nastavení prohlížeče; souhlas vyžaduje aktivní kliknutí.

### Google Consent Mode v2

- **CB-50 (MĚL BY)** Používá-li web GA4 nebo Google Ads, napojit lištu na Consent Mode v2 v režimu Basic: v něm se tagy Google nenačtou, dokud uživatel nesouhlasí. Režim Advanced spouští tagy už před souhlasem ([Lawwwing](https://lawwwing.com/en/blog/consent-mode-v2-resolvemos-tus-dudas)); s ohledem na CB-01 ho agent použije jen po výslovném rozhodnutí provozovatele.

### Přístupnost

- **CB-60 (MUSÍ)** Ovládání klávesnicí, viditelný fokus, logické pořadí tabulátoru, `role="dialog"` s `aria-labelledby`, přepínače jako `role="switch"` s `aria-checked`. Fokus se do lišty přesune jen u modální varianty.
- **CB-61 (MĚL BY)** Splnit WCAG 2.2 AA. Pro e-shopy, které nejsou mikropodnikem, je přístupnost od 28. 6. 2025 zákonná povinnost (zákon č. 424/2023 Sb.).
- **CB-62 (NESMÍ)** Automatické zmizení lišty po čase.

## Zakázané designové vzory

Cokoli, co odmítnutí ztěžuje oproti souhlasu, dělá souhlas neplatným. Seznam vychází z EDPB Cookie Banner Taskforce a z kategorií EDPB Guidelines 03/2022 (overloading, skipping, stirring, obstructing, fickle, left in the dark).

| ID | Nesmí se | Proč |
| --- | --- | --- |
| DP-01 | Odmítnutí jen ve druhé vrstvě nebo jen jako odkaz | Odmítnutí musí být stejně snadné jako souhlas |
| DP-02 | Zvýrazněné „Přijmout“ vs. šedé / průhledné „Odmítnout“ | Klamavé barvy a kontrast |
| DP-03 | Předem zapnuté přepínače kromě nezbytných | Planet49; recitál 32 GDPR |
| DP-04 | Formulace vyvolávající pocit viny nebo strach („Bez cookies web nebude fungovat“, pokud to není pravda) | Stirring – emoční nátlak |
| DP-05 | Opakované vyskakování lišty po odmítnutí v rámci 6 měsíců | Overloading – únava ze souhlasu |
| DP-06 | Kategorie „oprávněný zájem“ zapnutá ve výchozím stavu s nutností ji ručně vypínat | Obcházení souhlasu podle ZEK |
| DP-07 | Tlačítko „Uložit“ v druhé vrstvě, které ve skutečnosti přijme vše | Misleading action |
| DP-08 | Různé názvy pro totéž („Nastavení“, „Předvolby“, „Upravit“) na různých místech | Fickle – nekonzistentní rozhraní |
| DP-09 | Odkaz na odvolání souhlasu schovaný jen hluboko v Zásadách | Odvolání musí být stejně snadné |
| DP-10 | Lišta zakrývající obsah bez možnosti zavřít | Brání v používání webu (ÚOOÚ) |

## Stránka Zásady ochrany osobních údajů

Stránka musí obsahovat informace podle čl. 13 GDPR, uspořádané po účelech zpracování a dostupné jedním klikem z každé stránky webu. Název dokumentu je volný; rozhoduje srozumitelnost, stručnost a snadný přístup.

### Umístění a forma

- **PP-01 (MUSÍ)** Odkaz „Ochrana osobních údajů“ v patičce každé stránky; WP29 (WP260) doporučuje viditelný odkaz na každé stránce s jasným názvem.
- **PP-02 (MUSÍ)** U každého formuláře krátká informace vedle tlačítka odeslání (kdo, proč, odkaz na Zásady). Souhlasové checkboxy jen tam, kde je právním základem souhlas, nikdy předem zaškrtnuté.
- **PP-03 (MUSÍ)** Čeština, jednoduchý jazyk, bez proklikávání přes více stránek k základním informacím ([ÚOOÚ](https://uoou.gov.cz/verejnost/qa-otazky-a-odpovedi/cookies)).
- **PP-04 (MĚL BY)** Vrstvení: nahoře shrnutí v 3–5 větách, pod ním obsah s kotvami, pak detailní sekce. Tabulka „účel → údaje → právní základ → doba“ místo souvislého textu.
- **PP-05 (MĚL BY)** Na stránce Zásad a seznamu cookies lišta nepřekrývá obsah.
- **PP-06 (MUSÍ)** Datum účinnosti a verze; při změně historie změn na konci stránky.

### Povinný obsah

| Blok | Co obsahuje | Opora |
| --- | --- | --- |
| 1. Správce | Jméno nebo obchodní firma, sídlo / místo podnikání, IČO, zápis v rejstříku či evidenci, e-mail pro dotazy k osobním údajům | čl. 13 odst. 1 a); § 435 OZ |
| 2. Pověřenec | Kontakt na pověřence, je-li jmenován | čl. 13 odst. 1 b) |
| 3. Zpracování po účelech | Pro každý účel: kategorie údajů, právní základ (čl. 6 odst. 1 písm.), konkrétní oprávněný zájem, doba uložení nebo kritéria, zda je poskytnutí povinné a co hrozí při neposkytnutí | čl. 13 odst. 1 c), d); odst. 2 a), e) |
| 4. Příjemci | Zpracovatelé a další příjemci jmenovitě nebo po kategoriích (hosting, e-mail, účetní, analytika) | čl. 13 odst. 1 e) |
| 5. Předání mimo EU/EHP | Kam, na jakém základě (rozhodnutí o odpovídající ochraně, standardní smluvní doložky) | čl. 13 odst. 1 f) |
| 6. Práva | Přístup, oprava, výmaz, omezení, přenositelnost, odvolání souhlasu, stížnost u ÚOOÚ (Pplk. Sochora 27, 170 00 Praha 7) | čl. 13 odst. 2 b)–d) |
| 7. Námitka | Právo vznést námitku – samostatný, vizuálně oddělený blok | čl. 21 odst. 4 |
| 8. Automatizované rozhodování | Výslovně ano/ne; pokud ano, logika a důsledky | čl. 13 odst. 2 f) |
| 9. Cookies | Kategorie a tabulka položek ze stejného datového zdroje jako lišta + odkaz „Nastavení cookies“ | ZEK § 89/3; ÚOOÚ |
| 10. Uplatnění práv | Kontakt a způsob; odpověď do 1 měsíce | čl. 12 odst. 3 |
| 11. Společní správci | Jen varianta B1: podstata ujednání a kontaktní místo | čl. 26 odst. 2 |

### Katalog typických účelů (agent nabídne, provozovatel potvrdí)

| Účel | Obvyklý právní základ | Poznámka |
| --- | --- | --- |
| Odpověď na dotaz z formuláře / e-mailu | čl. 6/1 b) (jednání o smlouvě) nebo f) | Nevyžaduje souhlasový checkbox |
| Plnění smlouvy, fakturace | čl. 6/1 b) |  |
| Účetnictví a daně | čl. 6/1 c) | Dobu určí účetní / daňové předpisy – doplní provozovatel |
| Obchodní sdělení (newsletter) | souhlas, u stávajících zákazníků zákon č. 480/2004 Sb. | Ověřit s provozovatelem |
| Analytické a marketingové cookies | čl. 6/1 a) | Souhlas přes lištu |
| Provoz a zabezpečení webu (logy) | čl. 6/1 f) | Uvést konkrétní oprávněný zájem |
| Uplatnění a obrana právních nároků | čl. 6/1 f) |  |

### Doporučené pořadí na stránce

1. H1 „Ochrana osobních údajů“, datum účinnosti
2. Shrnutí (3–5 vět)
3. Box „Kdo je správce“ (karta pro každého správce)
4. Obsah s kotvami
5. Tabulka účelů
6. Příjemci a předání mimo EU
7. Vaše práva + samostatný blok Námitka
8. Cookies (tabulka + tlačítko „Nastavení cookies“)
9. Jak nás kontaktovat, stížnost u ÚOOÚ
10. Historie změn

## Varianty: jeden vs. více podnikatelů

U více podnikatelů na jednom webu agent nejdřív zjistí, kdo o čem rozhoduje; podle toho jsou společní správci (čl. 26), samostatní správci, nebo kombinace. Sdílená platforma sama o sobě společné správcovství nezakládá ([EDPB 07/2020](https://www.privacyworld.blog/2020/10/what-is-new-in-the-edpbs-draft-guidelines-on-controllers-and-processors-under-the-gdpr-part-3/)). Model agent nikdy neodhaduje.

**Rozhodnutí o modelu správců (2 otázky, 4 varianty)**

Otázka 1: Rozhodují podnikatelé společně o webu (obsah, formuláře, analytika, cookie lišta)?
Otázka 2: Zpracovávají společně i data klientů (smlouvy, fakturace, spisy), nebo každý své?

| Počet podnikatelů | Web a cookies | Klientská agenda | Varianta | `controllerModel` |
| --- | --- | --- | --- | --- |
| 1 | – | – | A – jeden správce | `single` |
| 2+ | společně | společně | B1 – společní správci | `joint` |
| 2+ | každý sám (web je jen společná výloha) | každý sám | B2 – samostatní správci | `separate` |
| 2+ | **společně** | **každý sám** | **B1 + B2 (kombinace)** | `hybrid` |

Zvýrazněná kombinace odpovídá situaci, kdy podnikatelé spravují web a cookies společně, ale klienty každý sám.

### Varianta A – jeden podnikatel (OSVČ nebo společnost)

- Jeden správce, jedna karta správce, lišta jmenuje tohoto správce.
- Identifikace podle § 435 OZ: jméno / obchodní firma, sídlo nebo místo podnikání, IČO, zápis (obchodní rejstřík, živnostenský rejstřík, seznam advokátů ČAK apod.).

### Varianta B1 – společní správci

Platí, když podnikatelé společně určují účely a prostředky zpracování: společný web, společný kontaktní formulář do sdílené schránky, společná analytika.

- **VAR-10 (MUSÍ)** Mezi správci existuje ujednání podle čl. 26; EDPB doporučuje závaznou formu (smlouvu).
- **VAR-11 (MUSÍ)** Na stránce Zásad blok „Společné správcovství“ s podstatou ujednání: kdo vyřizuje žádosti subjektů, kdo plní informační povinnost, kdo spravuje cookie lištu, kontaktní místo.
- **VAR-12 (MUSÍ)** Uvést, že práva lze uplatnit u kteréhokoli ze správců (čl. 26 odst. 3).
- **VAR-13 (MUSÍ)** Lišta v první vrstvě jmenuje všechny správce („Správci: X a Y, společní správci“).

### Varianta B2 – samostatní správci se společnou prezentací

Platí, když každý podnikatel zpracovává data svých klientů sám (vlastní smlouvy, fakturace, spisy) a web je jen společná výloha.

- **VAR-20 (MUSÍ)** Zásady mají společnou část pro provoz webu a cookies (se správcem webu, případně společnými správci webu) a samostatnou sekci pro každého podnikatele s jeho účely.
- **VAR-21 (MUSÍ)** Formulář s výběrem adresáta říká u tlačítka, že správcem poptávky je zvolená osoba.
- **VAR-22 (MĚL BY)** Sdílí-li podnikatelé web a analytiku, ale klienty mají každý své, použít kombinaci: web a cookies jako B1, klientská agenda jako B2.

### Společná pravidla pro více správců

- **VAR-30 (MUSÍ)** Každý správce úplně identifikován, stejná struktura karet (grid karet; u varianty A jedna karta).
- **VAR-31 (MUSÍ)** Tabulka účelů má sloupec „Správce“.
- **VAR-32 (MUSÍ)** Jeden kontaktní kanál pro uplatnění práv, i když jsou správci samostatní.
- **VAR-33 (MĚL BY)** U advokátů zohlednit [metodiku ČAK k GDPR](https://cak.cz/dokumenty-a-formulare/183) (mlčenlivost, evidence zpracování).

## Datový model (jediný zdroj pravdy)

Lišta, seznam cookies i stránka Zásad se generují z jednoho konfiguračního souboru; ruční duplikace textů vede k rozporům mezi lištou a Zásadami. Hodnoty `[DOPLNIT]` vyplní provozovatel, agent je nesmí odhadnout.

```json
{
  "configVersion": "1",
  "effectiveDate": "[DOPLNIT YYYY-MM-DD]",
  "language": "cs",
  "controllerModel": "single | joint | separate | hybrid",
  "controllers": [
    {
      "id": "ctrl-1",
      "legalForm": "OSVČ | s.r.o. | a.s. | advokát | …",
      "name": "[DOPLNIT jméno nebo obchodní firma]",
      "address": "[DOPLNIT sídlo / místo podnikání]",
      "ico": "[DOPLNIT]",
      "registry": "[DOPLNIT zápis v rejstříku / evidenci]",
      "privacyEmail": "[DOPLNIT]",
      "dpo": null
    }
  ],
  "jointArrangement": {
    "contactPointControllerId": "ctrl-1",
    "summary": "[DOPLNIT podstata ujednání dle čl. 26]"
  },
  "purposes": [
    {
      "id": "contact-form",
      "controllerIds": ["ctrl-1"],
      "title": "Odpověď na dotaz",
      "dataCategories": ["jméno", "e-mail", "text zprávy"],
      "legalBasis": "art6_1_b | art6_1_f | art6_1_a | art6_1_c",
      "legitimateInterest": null,
      "retention": "[DOPLNIT]",
      "recipientIds": ["rcp-hosting"],
      "mandatory": false,
      "consequenceIfNotProvided": "[DOPLNIT]"
    }
  ],
  "recipients": [
    {
      "id": "rcp-hosting",
      "name": "[DOPLNIT]",
      "role": "processor | controller | jointController",
      "country": "[DOPLNIT]",
      "transferBasis": "null | adequacyDecision | SCC"
    }
  ],
  "cookieCategories": [
    { "id": "necessary", "requiresConsent": false },
    { "id": "preferences", "requiresConsent": true },
    { "id": "analytics", "requiresConsent": true },
    { "id": "marketing", "requiresConsent": true },
    { "id": "thirdPartyContent", "requiresConsent": true }
  ],
  "items": [
    {
      "name": "[název cookie / klíče / pixelu]",
      "technology": "cookie | localStorage | sessionStorage | pixel | iframe",
      "categoryId": "analytics",
      "provider": "[DOPLNIT]",
      "party": "first | third",
      "purposeCs": "[účel česky]",
      "expiry": "[ověřit v prohlížeči]",
      "transferOutsideEEA": false
    }
  ],
  "consent": {
    "validityMonths": 12,
    "reaskAfterRejectMonths": 6,
    "googleConsentMode": "off | basic"
  },
  "automatedDecisionMaking": false,
  "changelog": []
}
```

**DM-01 (MUSÍ)** Změna v `purposes`, `controllers`, `recipients` nebo nová kategorie zvýší `configVersion` a vynutí nové zobrazení lišty (CB-42).

**DM-02 (MUSÍ)** `expiry` a seznam `items` se ověří skutečným měřením v prohlížeči (DevTools / sken), ne z dokumentace poskytovatele.

## Akceptační checklist

Výstup agenta je hotový, až projde všemi body v čistém profilu prohlížeče (bez cookies, bez rozšíření) na desktopu i na šířce 360 px.

**Před volbou**

- [ ] Po načtení: v DevTools žádné netechnické cookies, žádné klíče v localStorage mimo nezbytné, žádné požadavky na domény analytiky / reklamy (CB-01)
- [ ] Vložené video / mapa zobrazuje zástupný blok, ne iframe poskytovatele (CB-02)
- [ ] Web jde procházet a klikat i s otevřenou lištou (CB-03)
- [ ] Zavření lišty křížkem nic netechnického nespustí (CB-04)

**První vrstva**

- [ ] „Přijmout vše“ i „Odmítnout vše“ jsou tlačítka stejné velikosti a vizuální váhy, kontrast ≥ 4,5 : 1 (CB-10 až CB-12)
- [ ] Text uvádí správce, účely, třetí strany, možnost odvolání, odkaz na Zásady (CB-14)
- [ ] Na 360 px jsou obě tlačítka vidět bez scrollu (CB-15)

**Druhá vrstva**

- [ ] Všechny souhlasové přepínače vypnuté ve výchozím stavu (CB-20)
- [ ] Každá položka má český účel, poskytovatele, dobu platnosti; žádná „neklasifikovaná“ (CB-21, CB-23, INV-03)
- [ ] „Uložit výběr“ uloží jen zvolené kategorie (DP-07)

**Po volbě**

- [ ] „Odmítnout vše“ → po reloadu stále žádné netechnické položky, lišta se nezobrazí
- [ ] „Přijmout vše“ → skripty se načtou, uložen záznam souhlasu s verzí a časem (CB-40)
- [ ] Odkaz „Nastavení cookies“ v patičce otevře aktuální stav; odvolání smaže cookies první strany (CB-30, CB-31)
- [ ] Zvýšení `configVersion` → lišta se zobrazí znovu (CB-42)

**Zásady ochrany osobních údajů**

- [ ] Odkaz v patičce na každé stránce a u každého formuláře (PP-01, PP-02)
- [ ] Všech 11 bloků z tabulky „Povinný obsah“ vyplněno nebo výslovně „netýká se“
- [ ] Tabulka cookies na stránce odpovídá položkám v liště (stejný zdroj dat)
- [ ] U více správců: karta pro každého, sloupec „Správce“, blok o společném správcovství (VAR-\*)
- [ ] Žádný `[DOPLNIT]` v produkčním buildu

**Přístupnost**

- [ ] Celá lišta ovladatelná klávesnicí, viditelný fokus, čtečka ohlásí dialog a stav přepínačů (CB-60)

## Pravidla pro agenta

Agent navrhuje strukturu, design a chování; právní obsah nevymýšlí. Kde údaj chybí, vloží `[DOPLNIT]` a uvede ho v seznamu otevřených otázek pro provozovatele.

- **AG-01 (NESMÍ)** Vymýšlet identifikační údaje správce, doby uložení, právní základy, příjemce ani oprávněné zájmy.
- **AG-02 (NESMÍ)** Rozhodnout sám o modelu správců (A / B1 / B2 / kombinace); vždy se zeptá na otázky z diagramu výše.
- **AG-03 (NESMÍ)** Kopírovat obecné vzory privacy policy z internetu; každý účel musí odpovídat skutečnému zpracování na webu.
- **AG-04 (NESMÍ)** Použít šablonu CMP s výchozím nastavením bez kontroly proti CB-\* a DP-\*; lišty s odmítnutím jen ve druhé vrstvě ÚOOÚ opakovaně vytkl.
- **AG-05 (MUSÍ)** Předat provozovateli: inventář položek (INV-01), vyplněný konfigurační soubor, seznam `[DOPLNIT]`, výsledek checklistu.
- **AG-06 (MUSÍ)** Upozornit, že výsledek není právní posouzení; u neobvyklého zpracování (zdravotní údaje, děti, profilování, předání mimo EU bez rozhodnutí o odpovídající ochraně) doporučit konzultaci s advokátem.

## Výhled: Digital Omnibus

Na platných pravidlech se zatím nic nemění: návrh Digital Omnibus (COM(2025) 837 z 19. 11. 2025) je k září 2026 stále v legislativním procesu, takže platí ZEK a GDPR v dnešní podobě ([CookieScript](https://cookie-script.com/privacy-laws/eu-digital-omnibus-cookie-reform)).

- Návrh přesouvá pravidla pro cookies do nového čl. 88a GDPR; souhlas zůstává pravidlem, výjimky se rozšiřují mj. o agregované měření návštěvnosti a bezpečnost ([PwC](https://www.pwc.com/cz/cs/blog/pravo/digitalni-omnibus-konec-cookies-list-dil-3.html), [Syrenis](https://syrenis.com/resources/blog/proposed-new-cookie-exceptions-and-browser-signal-mandates/)).
- Čl. 88a by vyžadoval odmítnutí jedním klikem a zákaz opakovaného dotazu 6 měsíců po odmítnutí; použil by se 18 měsíců po nabytí účinnosti.
- Čl. 88b (souhlas signálem z prohlížeče) Rada EU podle dostupných zpráv z návrhu 18. 6. 2026 vypustila ([Gimii](https://gimii.fr/?p=130906)); Parlament stanovisko zatím nezaujal.

Dopad na tento design: CB-10 a CB-41 už odpovídají navrhovanému čl. 88a. Datový model počítá s `configVersion`, takže případné rozšíření výjimek (např. analytika bez souhlasu) bude znamenat jen přeřazení kategorie.

## Zdroje

**Úřad pro ochranu osobních údajů**

- [Q&A – Cookies](https://uoou.gov.cz/verejnost/qa-otazky-a-odpovedi/cookies)
- [Leták: Souhlas s cookies prostřednictvím cookie lišty](https://uoou.gov.cz/media/publikace/letaky-gdpr/3-letak-web.pdf)
- [Seminář: Praxe ÚOOÚ v oblasti cookies (06/2024)](https://uoou.gov.cz/media/seminare-uoou/prezentace/2024-06-12-p04-praxe-uoou-v-oblasti-cookies.pdf)
- [Příkaz UOOU-02482/22-9 (pokuta 602 000 Kč)](https://uoou.gov.cz/media/poskytnute-informace/2025/1292025/prikaz-cj-uoou-0248222-9.pdf)
- [Příkaz UOOU-02376/23-3 (justice.cz – chybí odmítnutí v 1. vrstvě)](https://uoou.gov.cz/media/poskytnute-informace/2023/17-8-2023/59-cj-uoou-0237623-3-dokument-c-59.pdf)
- [Příkaz UOOU-03056/23-3 (kr-vysocina.cz)](https://uoou.gov.cz/media/poskytnute-informace/2023/17-8-2023/62-cj-uoou-0305623-3-dokument-c-62.pdf)
- [Dokument UOOU-00747/23-4 („používáním webu souhlasíte“)](https://uoou.gov.cz/media/poskytnute-informace/2024/1742024-1/79-cj-uoou-0074723-4-dokument-c-79.pdf)

**EDPB a WP29**

- [Report Cookie Banner Taskforce – shrnutí Covington](https://www.insideprivacy.com/eu-data-protection/edpb-publishes-report-of-cookie-banners-taskforce/), [shrnutí Hunton](https://hunton.com/privacy-and-information-security-law/edpb-publishes-report-of-outcome-of-the-cookie-banner-taskforce)
- [Guidelines 2/2023 – technický rozsah čl. 5 odst. 3 ePrivacy](https://hunton.com/privacy-and-information-security-law/edpb-publishes-guidelines-to-clarify-scope-of-eu-cookie-notice-and-consent-requirements)
- [Guidelines 03/2022 – deceptive design patterns](https://www.edpb.europa.eu/our-work-tools/our-documents/guidelines/guidelines-032022-deceptive-design-patterns-social-media_en)
- [Guidelines 07/2020 – správce a zpracovatel (shrnutí)](https://www.privacyworld.blog/2020/10/what-is-new-in-the-edpbs-draft-guidelines-on-controllers-and-processors-under-the-gdpr-part-3/)
- [WP260 – transparentnost (shrnutí A&L Goodbody)](https://www.algoodbody.com/images/uploads/services/WP29_guidance_on_transparency_Dec_2017.pdf)

**Předpisy a judikatura**

- [GDPR čl. 26 (česky)](https://gdpr-text.com/cs/read/article-26/)
- [§ 435 občanského zákoníku](https://www.podnikatel.cz/zakony/novy-obcansky-zakonik/zneni-20230106/f4580257/)
- [SDEU C-40/17 Fashion ID – Advokátní deník](https://advokatnidenik.cz/2019/07/30/soudni-dvur-eu-k-odpovednosti-provozovatele-internetovych-stranek-a-prenos-dat-facebooku/)

**Články advokátů a specialistů**

- [epravo.cz – Cookies nově jen se souhlasem](https://www.epravo.cz/top/clanky/cookies-nove-jen-se-souhlasem-poslanecka-snemovna-prijala-zprisnujici-pravidla-od-roku-2022-113207.html)
- [Právní prostor – Sušenkové šílenství aneb cookies lišta v roce 2022](https://pravniprostor.cz/clanky/mezinarodni-a-evropske-pravo/susenkove-silenstvi-aneb-cookies-lista-v-roce-2022)
- [Právní prostor – sociální plug-iny a Fashion ID](https://pravniprostor.cz/clanky/ostatni-pravo/plug-in-ci-neplug-in-tot-otazka-aneb-socialni-plug-iny-ve-svetle-rozhodnuti-soudniho-dvora-evropske-unie-ve-veci-fashion-id)
- [epravo.cz – K odpovědnosti společných správců (NIELSEN MEINL)](https://www.epravo.cz/top/clanky/k-odpovednosti-spolecnych-spravcu-108827.html)
- [ČAK – Metodika pro advokáty k GDPR](https://cak.cz/dokumenty-a-formulare/183)
- [epravo.cz – Zákon o přístupnosti](https://www.epravo.cz/top/clanky/zakon-o-pristupnosti-120042.html)
- [PwC – Digitální omnibus: konec cookies lišt?](https://www.pwc.com/cz/cs/blog/pravo/digitalni-omnibus-konec-cookies-list-dil-3.html)
- [Grant Thornton – Cookie Rule Reform](https://www.grantthornton.cz/en/news/cookie-rule-reform-how-the-digital-omnibus-proposal-will-impact-reality/)
