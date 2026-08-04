# NEMEZIS
### Narodowa Ewidencja Mechanizmów Erozji Zamówień i Środków publicznych

> **„Konkurencja zostawia ślad. Jej brak zostawia rachunek."**

*Nemezis — grecka bogini odpłaty, karząca tych, którzy czerpią korzyść, na którą nie zasłużyli. Nie oskarża. Mierzy i wystawia rachunek.*

---

## I. Czym to jest w jednym zdaniu

Otwarty zbiór danych + raport analityczny w Power BI, który po raz pierwszy **wycenia w złotówkach koszt zaniku konkurencji w polskich przetargach publicznych** — gmina po gminie, zamawiający po zamawiającym — na podstawie ~1 mln realnych ogłoszeń z BZP i TED z lat 2021–2026, wzbogaconych o graf powiązań wykonawców z KRS i rejestrów skarbowych.

**Deliverable to NIE aplikacja.** To trzy artefakty:

1. **Data Product** — `nemezis-pl` : czysty, wersjonowany zbiór Parquet/CSV (postępowania + wykonawcy + wyliczone flagi ryzyka + graf powiązań), opublikowany z DOI na Zenodo i lustrzanie na dane.gov.pl / Hugging Face.
2. **Raport Power BI** — 5-stronicowa narracja śledcza z drill-through do pojedynczego przetargu.
3. **Whitepaper metodologiczny** (~15 stron PDF) — pełna, odtwarzalna definicja wskaźnika NRI wraz z walidacją statystyczną.

---

## II. Rdzeń problemu i „haczyk"

### Fakt, który jest publiczny, ale nikt go nie policzył do końca

**Polska jest liderem Unii Europejskiej pod względem odsetka przetargów, w których wpłynęła dokładnie jedna oferta.** W postępowaniach krajowych wskaźnik ten przekroczył 40%. Komisja Europejska szacuje, że zamówienia rozstrzygnięte na jedną ofertę są średnio **o ~9,6% droższe** od tych z realną konkurencją.

Nikt jednak nie powiedział Polakom:

> **Ile konkretnie kosztowała nas ta cisza? W złotówkach. W mojej gminie.**

### Haczyk

NEMEZIS zamienia abstrakcyjny odsetek w **kwotę na fakturze podatnika**. Wchodzisz na stronę, klikasz swoją gminę i widzisz:

> *Gmina X, 2021–2026: 1 240 postępowań, 58% rozstrzygniętych na jedną ofertę.
> Szacowana premia za brak konkurencji: **8,7 mln zł** — równowartość 34 km chodnika albo rocznego budżetu 2 przedszkoli.*

To jest moment „WOW". Nie wykres. **Przeliczenie statystyki na chodnik.**

### Trzy ukryte prawdy, które raport obnaża

| # | Odkrycie | Dlaczego to porusza |
|---|---|---|
| 1 | **Podatek od braku konkurencji** — pierwsza w Polsce oszacowana kwota nadpłaty publicznej, liczona metodą dopasowania (matching) w obrębie tej samej grupy porównawczej CPV × rok × typ zamawiającego × przedział wartości. | Konkretna liczba w mld zł, którą można podać w tytule artykułu. |
| 2 | **Pary zablokowane (buyer–supplier lock-in)** — zamawiający, u których ≥70% wartości od 3+ lat trafia do jednego wykonawcy, przy zerowej rotacji. | Nazwiska instytucji. Namacalne. Weryfikowalne. |
| 3 | **Graf „konkurentów"** — firmy startujące w tym samym postępowaniu, które dzielą adres, rachunek bankowy z białej listy VAT albo członka zarządu z KRS. | Klasyczna sygnatura *cover bidding*. Wizualnie druzgocąca. |

### Luka, którą wypełniamy (i to jest argument na nagrodę dziekana)

Europejski projekt **DIGIWHIST / opentender.eu** (Horizon 2020, grant nr 645852) pokrywa polskie dane **krajowe wyłącznie za lata 2008–2016**. Indeks Government Transparency Institute obejmuje tylko przetargi **powyżej progów unijnych**.

**Cały polski rynek krajowy poniżej progów UE po reformie ustawy PZP z 2021 r. — czyli dokładnie ten, w którym operują gminy, szpitale powiatowe i szkoły, i w którym problem jednej oferty jest najostrzejszy — nie został przeanalizowany przez nikogo publicznie.**

To nie jest „jeszcze jeden dashboard". To zamknięcie luki, której nie zamknął projekt finansowany przez Komisję Europejską.

---

## III. Źródła danych — wyłącznie realne, wyłącznie za 0 zł

### Warstwa 1: Rdzeń — postępowania (historia 2021–2026)

| Źródło | Co daje | Dostęp | Koszt |
|---|---|---|---|
| **API BZP WebService** (Platforma e-Zamówienia) `https://ezamowienia.gov.pl/mo-client-board/api/notices/` | Wszystkie ogłoszenia krajowe: o zamówieniu, o wyniku, o wykonaniu umowy. Kluczowe pola: liczba złożonych ofert, cena wybranej oferty, kwota przeznaczona na sfinansowanie, tryb, terminy, NIP wykonawcy, CPV. | REST, **bez wniosku dostępowego**, HTTPS/TLS 1.3 | 0 zł |
| **TED Bulk XML** (`ted.europa.eu/en/simap/xml-bulk-download` + FTP `guest/guest`) | Polskie ogłoszenia powyżej progów UE, format eForms od XI 2022. Paczki dzienne i miesięczne od 1993 r. | Pobranie ZIP/XML bez logowania | 0 zł |
| **Sprawozdania Prezesa UZP** (gov.pl, PDF) | Benchmark makro do walidacji: czy nasze agregaty zgadzają się z oficjalnymi. | PDF → parsing | 0 zł |

### Warstwa 2: Tożsamość i powiązania wykonawców

| Źródło | Co daje | Dostęp | Koszt |
|---|---|---|---|
| **Otwarte API KRS** `https://api-krs.ms.gov.pl/api/krs/OdpisAktualny/{KRS}` | Zarząd, wspólnicy, kapitał, data rejestracji, adres, status. | JSON, **bez autoryzacji**, limit 20 zapytań/min | 0 zł |
| **Wykaz podatników VAT — plik płaski** (MF, ~200 MB/dobę, publikowany codziennie ok. 00:01) | Pełne mapowanie NIP ↔ rachunki bankowe ↔ adres ↔ status VAT. **To jest paliwo do grafu powiązań** — brak limitów API, bo pobierasz cały plik. | Bezpośredni download z podatki.gov.pl | 0 zł |
| **API REGON/BIR (GUS)** | PKD, wielkość zatrudnienia, forma prawna, data powstania — dla podmiotów spoza KRS (JDG). | Darmowy klucz API | 0 zł |

### Warstwa 3: Kontekst i normalizacja

| Źródło | Co daje | Dostęp | Koszt |
|---|---|---|---|
| **API BDL GUS** `https://bdl.stat.gov.pl/api/v1/` | Ludność, dochody własne budżetu gminy, wydatki majątkowe — do normalizacji per capita i per budżet. | Darmowy klucz (`X-ClientId`) | 0 zł |
| **TERYT + granice administracyjne (GUGiK / PRG)** | Mapa choropleth w Power BI na poziomie gmin. | Shapefile → GeoJSON/TopoJSON | 0 zł |
| **Słownik CPV** (Publications Office EU) | Kategoryzacja przedmiotu zamówienia — podstawa grup porównawczych. | XML/CSV | 0 zł |

### Warstwa 4: Frontier — Centralny Rejestr Umów (nowość, od 1 lipca 2026)

**CRU** (`rejestrumow.gov.pl`) — obowiązek publikacji umów przez wszystkie jednostki sektora finansów publicznych ruszył **1 lipca 2026 r.**, czyli w tym miesiącu. Sieć Obywatelska Watchdog publicznie apeluje o otwarte API, bo **na razie go nie ma** — dane są dostępne wyłącznie rekord po rekordzie przez interfejs webowy.

**Konsekwencja:** ktokolwiek pierwszy zbuduje z CRU czysty, zbiorczy, otwarty zbiór danych, robi rzecz, której w Polsce nie zrobił jeszcze nikt. To jest moduł „aneksowy" NEMEZIS: **co się dzieje z ceną PO podpisaniu umowy.**

*Uwaga metodologiczna:* CRU ma miesiąc historii, więc to komponent prospektywny i rosnący — rdzeniem analizy pozostaje BZP + TED. Ale sam fakt bycia pierwszym to osobny, mocny punkt w portfolio.

**Zero danych symulowanych. Zero płatnych API. Zero szarej strefy prawnej — wszystko to oficjalne rejestry publiczne udostępniane do ponownego wykorzystania.**

---

## IV. Warsztat analityka — podział pracy

### Zasada
> Claude Code jest inżynierem danych. Człowiek jest analitykiem, statystykiem i narratorem.
> Claude nigdy nie decyduje, **co** znaczy „ryzyko". Człowiek nigdy nie pisze parsera XML ręcznie.

---

### A. Co koduje Claude Code (Python / SQL / DuckDB) — ok. 70% linii kodu, ok. 15% wartości intelektualnej

**A1. Akwizycja**
- Klient API BZP: OAuth2 (gdzie wymagane), paginacja, wznawianie od checkpointu, backoff, zapis surowych JSON-ów do `raw/` (immutable landing zone).
- Downloader paczek TED: dzienne/miesięczne ZIP-y, deduplikacja po `notice_id`.
- Parser eForms — najbrudniejsza robota w projekcie: schemat eForms SDK ma tysiące pól i kilkanaście wersji. Claude generuje mapowanie XPath → kolumna i obsługuje wersjonowanie schematu.
- Klient KRS z throttlingiem 20 req/min, cache lokalny SQLite (nie pytamy dwa razy o ten sam KRS).
- Parser pliku płaskiego MF (200 MB/dobę): streaming, bo nie wejdzie do RAM w całości.
- Scraper CRU: Playwright, respektowanie `robots.txt`, rate limit, snapshot dzienny + diff wykrywający aneksy.

**A2. Czyszczenie i entity resolution**
- Normalizacja NIP/REGON/KRS (walidacja sum kontrolnych, usunięcie myślników).
- Kanonizacja nazw firm: usunięcie form prawnych, transliteracja, `RapidFuzz` + blocking po pierwszych znakach + próg podobieństwa dobrany przez człowieka na ręcznie oznaczonej próbce 500 par.
- Kanonizacja adresów → mapowanie do TERYT.
- Deduplikacja zamawiających (ta sama gmina występuje w BZP pod 6 różnymi zapisami nazwy).

**A3. Modelowanie techniczne**
- Warstwa transformacji w DuckDB w stylu dbt: `staging → intermediate → marts`.
- Budowa grafu powiązań w `networkx`: wierzchołki = podmioty, krawędzie = wspólny rachunek bankowy / wspólny adres / wspólny członek zarządu. Wyznaczenie komponentów spójnych.
- Testy jakości danych (`pandera` / Great Expectations): unikalność kluczy, zakresy dat, brak ujemnych kwot, zgodność sum z raportem UZP.
- Eksport gwiazdy do Parquet + generacja `data_dictionary.md` i karty zbioru (datasheet).

---

### B. Co robi człowiek — ok. 30% linii kodu, ok. 85% wartości intelektualnej

**B1. Operacjonalizacja ryzyka — 11 flag (to jest serce projektu)**

| Flaga | Definicja operacyjna | Typ |
|---|---|---|
| `F1_JednaOferta` | liczba ofert = 1 | binarna |
| `F2_KrotkiTermin` | (termin składania − publikacja) w dniach, na tle percentyla dla danej grupy CPV × przedział wartości | ciągła |
| `F3_TrybNiekonkurencyjny` | wolna ręka / negocjacje bez ogłoszenia | binarna |
| `F4_CenaVsSzacunek` | cena wybranej oferty ÷ kwota przeznaczona na sfinansowanie | ciągła |
| `F5_KoncentracjaHHI` | HHI udziałów wykonawców u danego zamawiającego (okno kroczące 36 mies.) | ciągła |
| `F6_LockIn` | udział jednego wykonawcy w wartości zamawiającego ≥ 70% przez ≥ 3 lata | binarna |
| `F7_MlodyZwyciezca` | wiek podmiotu w KRS/REGON < 12 mies. w dniu rozstrzygnięcia | binarna |
| `F8_AnomaliaKalendarza` | publikacja ≤ 2 dni przed świętem / długim weekendem; termin składania w piątek po 12:00 | binarna |
| `F9_PowiazaniOferenci` | ≥ 2 oferentów w tym samym postępowaniu w jednym komponencie grafu | binarna |
| `F10_DzielenieZamowienia` | ≥ 3 umowy tego samego CPV, tego samego wykonawcy, w 90 dni, każda tuż poniżej progu 130 000 zł | binarna |
| `F11_InflacjaAneksowa` (CRU) | (wartość po aneksach − wartość pierwotna) ÷ wartość pierwotna | ciągła |

Każda flaga wymaga decyzji: próg, okno czasowe, obsługa brakujących danych, grupa odniesienia. **Tego nie da się zlecić modelowi — to jest dokładnie ta praca, za którą płaci się analitykowi.**

**B2. Grupy porównawcze i szacunek premii — najmocniejszy element statystyczny**

Naiwne „jedna oferta = drożej o 9,6%" to porównanie jabłek z gruszkami. Człowiek buduje **peer groups**: CPV (2 znaki) × rok × typ zamawiającego × decyl wartości × województwo, a następnie:

- **Coarsened Exact Matching** albo **propensity score matching** — dla każdego postępowania jednoofertowego szuka bliźniaka wieloofertowego.
- Estymacja premii cenowej jako różnicy w `F4_CenaVsSzacunek` między grupami.
- **Regresja z efektami stałymi**: `log(cena) ~ jedna_oferta + CPV_FE + rok_FE + zamawiajacy_FE + log(szacunek)` — kontrola nieobserwowalnych cech zamawiającego.
- **Testy odporności**: bootstrap CI, analiza wrażliwości na próg dopasowania, placebo test na latach przed reformą PZP.

Wynik: **premia z przedziałem ufności**, nie pojedyncza liczba. To odróżnia pracę naukową od infografiki.

**B3. Kompozyt NRI (NEMEZIS Risk Index, 0–100) i jego walidacja**

- Winsoryzacja + normalizacja rank-based każdej flagi ciągłej w obrębie peer group.
- Trzy warianty wag: (a) eksperckie z literatury DIGIWHIST, (b) pierwsza składowa PCA, (c) współczynniki regresji logistycznej.
- **Ground truth do walidacji**: orzeczenia KIO (uwzględnione odwołania) oraz wystąpienia pokontrolne NIK — zeskrapowane przez Claude'a jako etykiety pozytywne.
- Ocena: **ROC/AUC, precision@100, kalibracja**. Jeśli NRI nie odróżnia postępowań zaskarżonych i zakwestionowanych przez NIK lepiej niż losowo — indeks jest bezwartościowy i trzeba to uczciwie napisać.

*To jest punkt, który zamienia projekt studencki w miniaturę pracy naukowej.*

**B4. Model danych w Power BI (schemat gwiazdy)**

```
FAKTY:
  F_Postepowania      (ziarno: 1 część postępowania)   ~1 000 000 wierszy
  F_Umowy_CRU         (ziarno: 1 umowa/aneks)
  F_Oferty            (ziarno: 1 oferta w postępowaniu) — most many-to-many

WYMIARY:
  D_Zamawiajacy  (TERYT, typ jednostki, hierarchia woj→pow→gmina)
  D_Wykonawca    (NIP, wiek, PKD, ID komponentu grafu)
  D_Data         (role-playing: publikacja / termin / rozstrzygnięcie)
  D_CPV          (hierarchia 2→3→5→8 znaków)
  D_Tryb
  D_PeerGroup    (klucz surogatowy dla grupy porównawczej)

POMOSTY:
  B_Powiazania   (wykonawca ↔ komponent grafu, dla analizy cover bidding)
```

Decyzje architektoniczne po stronie człowieka: kierunki filtrowania, obsługa many-to-many oferty↔postępowania, agregacje wstępne dla warstwy mapowej, kompresja kolumn wysokiej kardynalności (NIP jako klucz surogatowy, nie tekst).

**B5. DAX — miary stanowiące serce raportu**

```dax
-- 1. Podstawa
Wsk. jednej oferty % =
DIVIDE(
    CALCULATE( COUNTROWS( F_Postepowania ), F_Postepowania[LiczbaOfert] = 1 ),
    COUNTROWS( F_Postepowania )
)

-- 2. Koncentracja rynku u zamawiającego (indeks Herfindahla-Hirschmana)
HHI wykonawców =
VAR Udzialy =
    ADDCOLUMNS(
        SUMMARIZE( F_Postepowania, D_Wykonawca[NIP_SK] ),
        "@Wartosc", CALCULATE( SUM( F_Postepowania[CenaWybrana] ) )
    )
VAR Calosc = SUMX( Udzialy, [@Wartosc] )
RETURN
    SUMX( Udzialy, DIVIDE( [@Wartosc], Calosc ) ^ 2 ) * 10000

-- 3. Serce projektu: premia za brak konkurencji w PLN
Premia za brak konkurencji =
VAR WspBazowy =                     -- benchmark z grupy porównawczej, wieloofertowej
    CALCULATE(
        AVERAGE( F_Postepowania[CenaDoSzacunku] ),
        REMOVEFILTERS( D_Zamawiajacy ),
        KEEPFILTERS( D_PeerGroup ),
        F_Postepowania[LiczbaOfert] > 1
    )
VAR WspFaktyczny =
    CALCULATE( AVERAGE( F_Postepowania[CenaDoSzacunku] ), F_Postepowania[LiczbaOfert] = 1 )
VAR WartoscJednoofertowa =
    CALCULATE( SUM( F_Postepowania[CenaWybrana] ), F_Postepowania[LiczbaOfert] = 1 )
RETURN
    DIVIDE( WspFaktyczny - WspBazowy, WspBazowy ) * WartoscJednoofertowa

-- 4. Przełożenie na język obywatela
Premia na mieszkańca =
DIVIDE( [Premia za brak konkurencji], SUM( D_Zamawiajacy[Ludnosc] ) )

Ekwiwalent w km chodnika =
DIVIDE( [Premia za brak konkurencji], [Sredni koszt km chodnika] )   -- z realnych umów CPV 45233

-- 5. Indeks kompozytowy z dynamicznymi wagami (parametr What-If)
NRI =
SUMX(
    D_Flagi,
    [Waga wybrana] * CALCULATE( AVERAGE( F_Flagi[WartoscZnorm] ) )
) * 100

-- 6. Ranking percentylowy zamawiającego w kraju
Percentyl NRI w kraju =
VAR Ranking =
    RANKX( ALL( D_Zamawiajacy ), [NRI], , ASC, DENSE )
VAR Ilu = COUNTROWS( ALL( D_Zamawiajacy ) )
RETURN DIVIDE( Ranking, Ilu )

-- 7. Trwałość zależności (lock-in)
Lata dominacji jednego wykonawcy =
COUNTROWS(
    FILTER(
        VALUES( D_Data[Rok] ),
        CALCULATE( [Udział największego wykonawcy] ) >= 0.7
    )
)
```

Dodatkowo: **grupy obliczeniowe** (calculation groups) dla time intelligence (YoY, rolling 12M, od reformy PZP), **parametry pól** (field parameters) do przełączania metryki na mapie, **RLS** po województwie dla wersji demonstracyjnej dla urzędów.

**B6. Narracja raportu (5 stron — projektuje człowiek)**

| Strona | Tytuł | Pytanie, na które odpowiada |
|---|---|---|
| 1 | **Rachunek** | Ile kosztował nas brak konkurencji? Jedna wielka liczba + mapa Polski. |
| 2 | **Mapa ciepła** | Gdzie jest najgorzej? Choropleth gmin wg NRI, z filtrami CPV i wartości. |
| 3 | **Ranking** | Kto wypada najgorzej wśród porównywalnych? Zamawiający zestawieni tylko z peer group — uczciwie. |
| 4 | **Profil zamawiającego** | Jak wygląda anatomia jednej instytucji? Timeline, portfel wykonawców, HHI w czasie. |
| 5 | **Śledztwo** | Drill-through do pojedynczego przetargu: wszystkie flagi, graf oferentów, link do oryginalnego ogłoszenia w BZP. |

Kluczowa decyzja narracyjna: **każdy zamawiający porównywany jest wyłącznie do swojej grupy odniesienia.** Mała gmina wiejska nie stoi obok Warszawy. To odbiera raportowi zarzut nieuczciwości — i jest dokładnie tym, co doceni komisja.

---

### C. Roadmapa — 10 tygodni

| Tydzień | Zakres | Kto prowadzi |
|---|---|---|
| 1 | Rozpoznanie API BZP i TED, próbka 5 000 ogłoszeń, decyzja o ziarnie danych | Człowiek |
| 2–3 | Pełna akwizycja BZP + TED, parser eForms, landing zone | Claude |
| 4 | Wzbogacenie: KRS, plik płaski MF, REGON, BDL | Claude |
| 5 | Entity resolution + graf powiązań, ręczna walidacja 500 par | Wspólnie |
| 6 | Definicja i implementacja 11 flag, budowa peer groups | Człowiek |
| 7 | Matching + regresja + bootstrap; walidacja NRI na KIO/NIK | Człowiek |
| 8 | Model gwiazdy, ~30 miar DAX, grupy obliczeniowe | Człowiek |
| 9 | Projekt wizualny 5 stron, drill-through, testy UX na 3 osobach spoza branży | Człowiek |
| 10 | Publikacja: Zenodo (DOI) + GitHub + whitepaper + wysyłka do 3 redakcji i Sieci Obywatelskiej Watchdog | Wspólnie |

---

### D. Ryzyka i etyka — sekcja, bez której komisja obetnie punkty

| Ryzyko | Mitygacja |
|---|---|
| **Zarzut pomówienia** | Raport nazywa się *indeksem ryzyka*, nie *indeksem korupcji*. Każda strona zawiera stopkę: wysoki NRI oznacza wzorzec statystyczny wymagający wyjaśnienia, nie zarzut. Publikujemy procedurę zgłaszania sprostowań. |
| **RODO** | Operujemy wyłącznie na danych podmiotów gospodarczych i jawnych rejestrach. API KRS zwraca dane zanonimizowane w zakresie danych osobowych. Nie publikujemy PESEL ani adresów zamieszkania. |
| **Niekompletność danych** | Karta zbioru (datasheet) jawnie deklaruje pokrycie, braki i znane błędy źródeł. Walidacja agregatów względem sprawozdań UZP. |
| **Fałszywe alarmy grafu** | Wspólny adres w biurze wirtualnym ≠ zmowa. Odfiltrowanie znanych adresów wirtualnych biur; wymagane ≥ 2 niezależne sygnały, by oznaczyć krawędź jako istotną. |
| **Stabilność darmowych API** | Otwarte API KRS nie gwarantuje ciągłości działania. Stąd cache lokalny i preferencja dla pobierania plików zbiorczych (plik płaski MF, paczki TED) nad odpytywaniem rekord po rekordzie. |
| **Skala** | ~1 mln postępowań × ~120 kolumn to ok. 3–6 GB w Parquet — mieści się na laptopie w DuckDB. Power BI w trybie import po agregacji: < 400 MB. Wykonalne bez chmury. |

---

## V. Dlaczego to rozwala rekruterów i komisję dziekańską

### Sygnał wysyłany rekruterowi

Typowe portfolio juniora: Netflix EDA, Titanic, sprzedaż z Kaggle. Dane gotowe, pytanie zadane przez kogoś innego, wnioski oczywiste.

NEMEZIS dowodzi **pięciu kompetencji, których nie da się udawać**:

1. **Pozyskiwanie danych, których nikt ci nie poda w CSV.** REST + OAuth2 + parsing eForms XML + scraping + throttling + entity resolution. To jest pierwsze 80% pracy analityka w firmie i pierwsze 80% pracy, której nie widać w projektach z Kaggle.
2. **Entity resolution i myślenie grafowe.** Sklejenie „ABC Sp. z o.o." z „A.B.C. spółka z ograniczoną odpowiedzialnością" po NIP, adresie i rachunku bankowym to codzienność w KYC, AML, ubezpieczeniach i wykrywaniu fraudu. Bank, ubezpieczyciel i dział compliance czytają to jako gotowy sygnał.
3. **Poprawność przyczynowa, nie tylko korelacja.** Peer groups, matching, efekty stałe, przedziały ufności, testy odporności. Umiejętność powiedzenia „ta różnica może wynikać z X, więc kontroluję X" to granica między analitykiem a osobą robiącą wykresy.
4. **Dojrzały warsztat BI.** Schemat gwiazdy z pomostem many-to-many, grupy obliczeniowe, parametry pól, RLS, świadome zarządzanie kardynalnością — to poziom seniora, nie kursu online.
5. **Narracja i odpowiedzialność.** Przeliczenie premii na „km chodnika", uczciwe porównania w grupach odniesienia, jawna sekcja ograniczeń i procedura sprostowań. Rekruter widzi kogoś, komu można powierzyć raport idący do zarządu — i do prasy.

**Zdanie, które kończy rozmowę kwalifikacyjną:**
> „Zbudowałem otwarty zbiór danych obejmujący milion polskich przetargów i oszacowałem, że brak konkurencji kosztuje sektor publiczny X mld zł rocznie. Zbiór ma DOI, metodologia jest w pełni odtwarzalna, a indeks ryzyka jest zwalidowany na orzeczeniach KIO. Cały pipeline stoi na darmowych rejestrach publicznych."

### Sygnał wysyłany komisji dziekańskiej

Nagroda dziekana nie idzie do najładniejszego dashboardu. Idzie do pracy, która ma **wkład, metodę i odbiorcę**.

| Kryterium | Jak NEMEZIS je spełnia |
|---|---|
| **Nowość** | Polski rynek krajowy poniżej progów UE po reformie PZP 2021 nie został publicznie przeanalizowany. opentender.eu kończy polskie dane krajowe na 2016 r. Luka jest weryfikowalna i możliwa do zacytowania. |
| **Rygor metodologiczny** | Matching + efekty stałe + bootstrap + walidacja indeksu na zewnętrznym ground truth (KIO/NIK) z AUC. To jest aparat pracy naukowej, nie projektu zaliczeniowego. |
| **Odtwarzalność** | Cały pipeline w repozytorium, dane wersjonowane, DOI na Zenodo, karta zbioru. Recenzent może odtworzyć wynik jednym poleceniem. |
| **Wkład otwarty** | Zbiór danych jest samodzielnym produktem — mogą go użyć dziennikarze, NGO, doktoranci i inne uczelnie. Cytowalność to najmocniejszy argument przed komisją. |
| **Znaczenie społeczne** | Temat leży w centrum polityki publicznej: Polska ma najwyższy w UE odsetek przetargów z jedną ofertą, a Centralny Rejestr Umów właśnie ruszył. Trafienie w moment jest idealne. |
| **Interdyscyplinarność** | Informatyka (inżynieria danych, grafy) + ekonometria (wnioskowanie przyczynowe) + prawo zamówień publicznych + komunikacja danych. Dokładnie ten przekrój, który komisje nagradzają. |

### Ścieżka wzmocnienia (opcjonalna, ale podnosi sufit)

- Zgłoszenie zbioru na **dane.gov.pl** jako danych pochodnych — oficjalny ślad instytucjonalny.
- Kontakt z **Siecią Obywatelską Watchdog**, która publicznie domaga się otwartych danych z CRU — realny partner i realna dystrybucja.
- Krótki artykuł metodologiczny na arXiv / w czasopiśmie uczelnianym → cytowanie.
- Jeden mocny wątek do mediów: „Gminy, w których konkurencja zniknęła" — publikacja prasowa jest w oczach komisji dowodem oddziaływania.

---

## Podsumowanie w trzech zdaniach

NEMEZIS bierze milion prawdziwych, darmowych, publicznych rekordów przetargowych i odpowiada na pytanie, którego nikt w Polsce nie policzył do końca: **ile realnie kosztuje nas brak konkurencji, gmina po gminie.**

Claude Code wykonuje całą inżynierię — API, parsery, scrapery, entity resolution, graf powiązań — a analityk robi to, za co się płaci: definiuje ryzyko, buduje grupy porównawcze, szacuje efekt metodą przyczynową, projektuje model gwiazdy, pisze DAX i buduje narrację.

Efektem nie jest aplikacja, tylko **otwarty produkt danych z DOI, zwalidowany indeks ryzyka i raport, który da się zacytować w gazecie, na obronie i na rozmowie kwalifikacyjnej.**
