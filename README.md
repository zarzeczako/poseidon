# P.O.S.E.I.D.O.N.

**P**ublic **O**rder & **S**ystemic **E**rosion **I**nvestigative **D**ata **O**bservation **N**etwork

> Konkurencja zostawia ślad. Jej brak zostawia rachunek.

Projekt analityczno-śledczy, który po raz pierwszy wycenia w złotówkach koszt zaniku
konkurencji w polskich przetargach publicznych — gmina po gminie, zamawiający po
zamawiającym.

## O co chodzi

Polska ma najwyższy odsetek przetargów w Unii Europejskiej, w których wpłynęła dokładnie
jedna oferta — w postępowaniach krajowych ponad 40%. Komisja Europejska szacuje, że
zamówienia rozstrzygnięte na jedną ofertę są średnio o ok. 9,6% droższe niż te z realną
konkurencją. Nikt jednak nie przełożył tego procentu na konkretną kwotę: ile kosztowała
dana gmina cisza konkurencyjna w jej własnych przetargach.

P.O.S.E.I.D.O.N. łączy dane z **BZP** (krajowa platforma e-Zamówienia) i **TED** (unijny
dziennik zamówień) z lat 2021–2026, godzi je ze sobą, wzbogaca o graf powiązań wykonawców
(KRS, biała lista VAT) i liczy 11 wskaźników ryzyka — m.in. jedną ofertę, nietypowo krótkie
terminy, koncentrację rynku (HHI), trwałe "zablokowane pary" zamawiający–wykonawca oraz
sygnatury zmowy przetargowej (*cover bidding*) w grafie oferentów.

Analogiczny projekt europejski (DIGIWHIST/opentender.eu) pokrywa polskie dane krajowe
tylko do 2016 r. i tylko powyżej progów unijnych. Rynek krajowy poniżej tych progów — czyli
dokładnie ten, w którym działają gminy, szpitale powiatowe i szkoły — nie doczekał się
dotąd publicznej, odtwarzalnej analizy.

## Co powstanie

1. **Otwarty zbiór danych** — postępowania, wykonawcy, wyliczone flagi ryzyka i graf
   powiązań, publikowany z pełną metodologią.
2. **Raport Power BI** — narracja śledcza z drill-through do pojedynczego przetargu.
3. **Whitepaper metodologiczny** — odtwarzalna definicja kompozytowego indeksu ryzyka,
   z walidacją statystyczną (dopasowanie w grupach porównawczych, regresja z efektami
   stałymi, bootstrap, weryfikacja na rozstrzygnięciach KIO/raportach NIK).

## Stan projektu (04.08.2026)

Projekt jest w **Fazie 1 — Akwizycja danych**, w toku.

- Rozpoznane i udokumentowane API BZP (`Board/Search` + `GetNoticeHtmlBodyById`) i TED
  (Search API v3) — bez autoryzacji, oba za 0 zł.
- Baza danych: PostgreSQL (Neon, serverless), warstwa `staging` (surowe dane) → `core`
  (godzenie BZP↔TED z dwupoziomowym dopasowaniem: twarda referencja + fuzzy po NIP/REGON
  z tolerancją ±7 dni / ±2% wartości).
- Klienty akwizycyjne (`etl/fetch_bzp.py`, `etl/fetch_ted.py`) oraz parser
  ustandaryzowanego formularza ogłoszeń BZP (`etl/parse_bzp_form.py`) działają end-to-end
  i są zweryfikowane na żywych danych.
- Zakres i harmonogram pełnej akwizycji historycznej (ok. 3,25 mln ogłoszeń w BZP,
  zawężone do dwóch najistotniejszych typów ogłoszeń) są ustalone; sama pełna akwizycja
  jeszcze nieodpalona — trwają ostatnie kroki przygotowawcze.
- Kolejne fazy (wzbogacenie o KRS/VAT/GUS, entity resolution i graf powiązań, definicja
  flag ryzyka, modelowanie i regresja, model gwiazdy Power BI, publikacja) czekają na
  ukończenie akwizycji.

Pełny dziennik decyzji technicznych i bieżący stan prac prowadzone są lokalnie i nie
wchodzą w skład tego repozytorium.
