# POSEIDON_GUIDE.md — Ledger Architekta

> Dziennik decyzji technicznych projektu P.O.S.E.I.D.O.N. Cel podwójny: (1) nigdy nie zgubić kontekstu "dlaczego zrobiliśmy to tak, a nie inaczej", (2) zbudować gotowy zestaw odpowiedzi na rozmowy kwalifikacyjne DA/BA.

---

## Format wpisu

```
### [Faza] Tytuł decyzji
**Decyzja:** co wybraliśmy
**Odrzucone alternatywy:** co rozważaliśmy i dlaczego NIE ("jabłka vs marchewki" — porównujemy uczciwie, nie ze słomianym przeciwnikiem)
**Dlaczego:** logika biznesowa/techniczna, konsekwencje wyboru
**Q&A rekrutacyjne:** pytanie, jakie mógłby zadać rekruter/promotor + gotowa odpowiedź
```

---

## Faza 0 — Fundamenty projektu

### Rebranding: NEMEZIS → P.O.S.E.I.D.O.N.

**Decyzja:** Projekt operuje pod nazwą P.O.S.E.I.D.O.N. (Public Order & Systemic Erosion Investigative Data Observation Network), z motywem boga mórz.

**Odrzucone alternatywy:** Utrzymanie nazwy NEMEZIS (bogini odpłaty) — mocna metafora ("mierzy i wystawia rachunek"), ale węższa niż zakres projektu. NEMEZIS sugeruje wyłącznie karanie; projekt to w równym stopniu eksploracja (nurkowanie w danych), wykrywanie struktur relacyjnych (graf/prądy powiązań) i wstrząs systemowy (wpływ raportu na audyt).

**Dlaczego:** Nazwa i motyw to pierwszy sygnał narracyjny w portfolio — zanim ktokolwiek zobaczy kod czy DAX. Trzy warstwy motywu Posejdona (eksploracyjna / relacyjna / sejsmiczna) mapują się wprost na trzy warstwy projektu (akwizycja / graf powiązań / impact raportu).

**Q&A rekrutacyjne:**
> **Q: Dlaczego nazwa i spójna metafora mają znaczenie w projekcie analitycznym?**
> A: Bo to pierwsze 30 sekund kontaktu z projektem, zanim ktokolwiek oceni metodologię. Konsekwentnie utrzymana metafora w nazwach modułów i w narracji raportu pokazuje umiejętność komunikacji danych (data storytelling), nie tylko samą analizę — a to jest dokładnie to, czego szuka się u seniora, nie u junior-analityka klepiącego wykresy.

---

## Faza 1 — Akwizycja danych

### PostgreSQL zamiast DuckDB

**Decyzja:** Backend to PostgreSQL, nie DuckDB (jak sugerowała pierwotna koncepcja).

**Odrzucone alternatywy:** DuckDB — embedded, zero-infra, świetny do czystego OLAP-crunchu ~1 mln wierszy na laptopie bez serwera.

**Dlaczego:** PostgreSQL wymaga uruchomionego serwera (cięższa operacyjnie), ale daje dojrzałe funkcje/procedury PL/pgSQL, prawdziwy współbieżny dostęp i naturalnie wspiera wzorzec "SQL jako jedyna warstwa transformacji" (widoki + funkcje), który Architekt wybrał dla Fazy 1. To świadomy kompromis: więcej ops, więcej możliwości proceduralnych.

**Q&A rekrutacyjne:**
> **Q: Kiedy wybrałbyś Postgres, a kiedy DuckDB, do projektu analitycznego tej skali?**
> A: DuckDB, gdy priorytetem jest zero-infra i szybki OLAP na pojedynczej maszynie (np. jednorazowa analiza, prototyp). Postgres, gdy potrzebujesz współbieżnego dostępu, dojrzałych proceduralnych widoków/funkcji jako warstwy transformacji, i architektury bliższej temu, co spotkasz w produkcyjnym środowisku firmowym — nawet kosztem utrzymania serwera.

### Godzenie BZP ↔ TED: dwupoziomowe dopasowanie z wzajemnym najlepszym dopasowaniem

**Decyzja:** Poziom 1 — twarda referencja (numer ogłoszenia TED zacytowany w BZP, gdy dostępny). Poziom 2 — fuzzy match (NIP zamawiającego + data ±7 dni + wartość ±2%), ale tylko gdy dopasowanie jest wzajemnie najlepsze po obu stronach (dual `ROW_NUMBER()`), nie zwykły `JOIN`.

**Odrzucone alternatywy:** Zwykły `JOIN` na kryteriach fuzzy zaproponowany pierwotnie przez Architekta — odrzucony, bo przy 2+ podobnych przetargach tego samego zamawiającego w tym samym oknie czasowym tworzy fan-out (jeden rekord BZP dopasowuje się do wielu TED i odwrotnie), co z powrotem duplikuje dane, tylko inną drogą niż brak deduplikacji w ogóle.

**Dlaczego:** Wymaganie wzajemności (b najlepsze dla t I t najlepsze dla b) to tania w SQL (dwa okna analityczne) gwarancja 1:1, bez potrzeby pełnego stable-matching algorytmu. Przegrani kandydaci nie znikają — lądują w `core.v_matches_needs_review` do przeglądu, zamiast być cicho odrzuceni albo cicho zduplikowani.

**Q&A rekrutacyjne:**
> **Q: Dlaczego zwykły JOIN na przybliżonych kryteriach (fuzzy match) jest ryzykowny przy łączeniu dwóch źródeł?**
> A: Bo fuzzy match nie gwarantuje kardynalności 1:1 — jeśli więcej niż jeden rekord po drugiej stronie spełnia kryteria tolerancji, JOIN zwróci iloczyn kartezjański tych dopasowań, mnożąc wiersze zamiast je scalać. Rozwiązanie to ranking + wymóg wzajemności najlepszego dopasowania (mutual nearest-neighbor), a nie samo zawężanie progów tolerancji — bo nawet wąskie progi nie eliminują kolizji przy gęsto upakowanych danych.

### Konflikt kwot BZP vs TED: trzymamy obie wartości, nie wybieramy jednej

**Decyzja:** `core.postepowania_polaczone` trzyma `kwota_bzp`, `kwota_ted` i `rozbieznosc_kwot_pct` jako osobne kolumny. Żadna nie jest automatycznie "tą jedyną słuszną" na etapie godzenia.

**Odrzucone alternatywy:** Przyjęcie kwoty z TED jako bazowej dla całego zbioru (pierwotna propozycja Architekta) — odrzucone, bo TED czasem raportuje kwoty w innej konwencji (bliżej netto, zaokrąglenia unijne) niż polska kwota brutto z BZP; ciche przyjęcie jednej wartości mogłoby wprowadzić systematyczne obciążenie (bias) do głównej metryki projektu bez śladu w danych.

**Dlaczego:** Decyzja, której kwoty użyć jako kanonicznej przy liczeniu `Premia za brak konkurencji`, wymaga zobaczenia realnej skali rozbieżności na danych — to należy do Fazy 4/5 (peer groups, matching), nie do warstwy godzenia w Fazie 1. Zatwierdzone przez Architekta 2026-08-03.

**Q&A rekrutacyjne:**
> **Q: Dlaczego czasem lepiej NIE rozstrzygać konfliktu danych na etapie ETL, tylko przenieść decyzję dalej?**
> A: Bo wybór "zwycięskiej" wartości w warstwie ETL jest nieodwracalny i niewidoczny dla analityka pracującego już na czystych danych — ślad konfliktu ginie. Zatrzymanie obu wartości + metryki rozbieżności pozwala podjąć tę decyzję świadomie, na podstawie realnej dystrybucji rozbieżności, i udokumentować ją jako osobny krok metodologiczny.

### Hosting PostgreSQL: Neon (managed, serverless)

**Decyzja:** Baza żyje w chmurze jako managed serverless Postgres na Neon — nie lokalnie, nie na własnoręcznie stawianej maszynie.

**Odrzucone alternatywy:**
- *Lokalny Postgres* — zero kosztów/setupu, ale dostępny tylko z jednej maszyny; słabszy sygnał w portfolio ("działa u mnie na laptopie").
- *Docker + VM w chmurze* — najwięcej nauki realnego devopsu (sieć, firewall, wolumeny, backupy), ale godziny pracy niezwiązanej z analizą danych — projekt ma dowieźć DA/BI/causal inference, nie SRE.
- *Supabase* — też managed/serverless, ale dokłada auth/storage/realtime/auto-API, których POSEIDON nie potrzebuje (Power BI łączy się bezpośrednio jako Postgres). Darmowy projekt usypia po ok. tygodniu bezczynności i wymaga ręcznego wybudzenia z panelu.
- *AWS RDS / Azure Database / GCP Cloud SQL* — enterprise-grade, ale płatne poza okresem próbnym i cięższe w konfiguracji niż potrzeba na tym etapie.

**Dlaczego:** Neon daje czysty Postgres bez zbędnych warstw, autosuspend/autowznowienie bez ręcznej interwencji, i darmowy tier z zapasem na skalę tego projektu. Najlepszy balans: zero-ops, ale nadal "prawdziwa chmura" w CV, bez odciągania czasu od pracy analitycznej.

**Q&A rekrutacyjne:**
> **Q: Jak wybierasz między self-hosted a managed bazą danych w projekcie małej/średniej skali?**
> A: Pytam, co faktycznie chcę pokazać/nauczyć się i ile operacyjnego narzutu jestem gotów utrzymywać. Self-hosted (Docker+VM) uczy realnej infrastruktury, ale kosztuje czas niezwiązany z celem projektu. Managed serverless (Neon) daje "prawdziwą chmurę" bez tego narzutu — właściwy wybór, gdy projekt ma dowieźć wynik analityczny, nie kompetencję DevOps.

### Rozpakowanie wieloczęściowych postępowań: normalizacja przed unnest, nie unnest na oślep

**Decyzja:** `staging.v_bzp_parts` normalizuje `contractors` jawnym `CASE jsonb_typeof(...)` (obiekt →
opakuj w tablicę jednoelementową; tablica → zostaw) PRZED próbą `jsonb_array_elements(...) WITH ORDINALITY`.

**Odrzucone alternatywy:** Zakładanie, że `contractors` zawsze jest tablicą i rozpakowywanie wprost —
odrzucone, bo na realnych danych potwierdzono, że przy dokładnie 1 części `contractors` jest gołym
obiektem JSON, nie tablicą jednoelementową. Bez normalizacji `jsonb_array_elements()` albo wywali błąd,
albo (gorzej) zwróci błędne dane dla najprostszego, najczęstszego przypadku (postępowanie jednoczęściowe).

**Dlaczego:** To był pomysł Architekta ("po prostu ifem") — słuszny w duchu, tu sformalizowany jako
idiomatyczny wzorzec Postgresa: `CASE` normalizuje kształt, `WITH ORDINALITY` zachowuje pozycję (`ord`),
żeby dało się ją później zestawić 1:1 z pozycją w `procedureResult` (rozdzielonym średnikiem) — to jest
część, której sam "if" by nie załatwił: nie wystarczy obsłużyć oba kształty, trzeba też nie zgubić, który
wynik należy do którego kontrahenta.

**Q&A rekrutacyjne:**
> **Q: Jak radzisz sobie z API, które zwraca niespójny kształt JSON w zależności od liczby elementów (obiekt vs tablica jednoelementowa)?**
> A: Normalizuję kształt jawnie na wejściu (`jsonb_typeof` + `CASE`) zamiast pisać kod, który zakłada jeden kształt i się wywraca na drugim. W Postgresie dodatkowo pilnuję pozycji przez `WITH ORDINALITY`, jeśli dalsza logika zależy od kolejności elementów względem innego, równoległego pola.

### Flaga `czy_osoba_fizyczna` zamiast cichej utraty danych w NIP

**Decyzja:** `staging.v_bzp_parts.wykonawca_czy_osoba_fizyczna` odróżnia "wykonawca to osoba fizyczna bez
NIP" (`contractorNationalId` = tekst typu "brak - podmiot nie prowadzący działalności gospodarczej") od
"brak danych" (`contractorNationalId` = NULL, np. unieważniona część postępowania).

**Odrzucone alternatywy:** Zostawienie samego `wykonawca_nip = NULL` bez dodatkowej flagi — odrzucone,
bo to zaciera różnicę między "nie wiemy" a "wiemy, że to osoba fizyczna" — a to druga rzecz jest realnym,
analitycznie ciekawym sygnałem (np. do przyszłej analizy: czy małe zamówienia trafiają częściej do osób
fizycznych bez działalności).

**Dlaczego:** Zatwierdzone przez Architekta 2026-08-04. Koszt utrzymania tej flagi jest zerowy (jedna
kolumna wyliczana), a odzyskuje informację, którą inaczej byśmy bezpowrotnie spłaszczyli do NULL.

**Q&A rekrutacyjne:**
> **Q: Dlaczego "brak danych" i "wiemy, że tej wartości nie ma z konkretnego powodu" to nie to samo w modelu danych?**
> A: Bo NULL jest przeciążony — miesza ze sobą różne przyczyny brakujących danych (błąd źródła, faktyczny brak, nie dotyczy) w jedną wartość, którą traktuje się jednakowo we wszystkich dalszych agregacjach. Jeśli konkretna przyczyna ma wartość analityczną, wart jest osobnej flagi, żeby nie trzeba jej było odgadywać na końcu pipeline'u.

### Parsowanie SEKCJA VI-VIII z htmlBody: Python, regex na stałych kodach pól

**Decyzja:** `etl/parse_bzp_form.py` wyciąga ponumerowane pola formularza (`6.1.)`, `6.2.)`, `8.2.)` itd.)
z `htmlBody` przez regex na wzorcu `<h3...>{KOD}.) {ETYKIETA}: <span class="normal">{WARTOŚĆ}</span>`,
strukturalnie (bez decyzji biznesowych, bez typowania wartości) — spójnie z tym, jak Python traktuje XML z TED.

**Odrzucone alternatywy:** `regexp_matches()` bezpośrednio w SQL — odrzucone z tego samego powodu co przy
TED: przy wieloletnim zbiorze (2021-2026) i możliwych zmianach szablonu formularza w czasie, utrzymanie
takiej logiki jako widoków SQL byłoby nie do ogarnięcia. Python trzyma tę złożoność w jednym, testowalnym miejscu.

**Dlaczego:** SEKCJA V-VIII powtarzają się per "Część N" w treści HTML, ale znacznik części bywa
wyrażony na dwa różne sposoby (`<h3>Część N</h3>` ALBO `(dla części N)` w nagłówku SEKCJA) — i przy
postępowaniu **jednoczęściowym formularz w ogóle pomija numerację części**. Odkryte dopiero przy
faktycznym uruchomieniu parsera na 3 realnych próbkach (nie teoretycznie): bez jawnej reguły "SEKCJA
V-VIII bez żadnego znacznika = domyślnie Część 1" pola jednoczęściowych postępowań lądowały w nagłówku
zamiast w `czesci[1]` — niespójnie z wieloczęściowymi. Poprawione i zwalidowane przed dostarczeniem.

**Ograniczenie środowiskowe:** Python nie jest zainstalowany na tej maszynie (tylko pusta zaślepka
Microsoft Store) — logika była walidowana 1:1 przez odpowiednik w PowerShell na realnych danych z
`recon/`, ale sam plik `.py` nie został jeszcze uruchomiony. Patrz `STATE.md` §4.

**Q&A rekrutacyjne:**
> **Q: Skąd wiadomo, że parser strukturalny (regex na formularzu) jest "bezpieczny", skoro to wciąż parsowanie HTML?**
> A: Bo różnica nie jest "HTML vs nie-HTML", tylko "czy źródło ma stały, wymuszony prawnie kontrakt formatu". Tu kody pól (6.1, 6.2...) pochodzą z rozporządzenia, nie z czyjegoś swobodnego HTML-a — więc parser można zwalidować raz na próbce i traktować odchylenia (kod się nie znalazł, wartość się nie sparsowała) jako sygnał do przeglądu, a nie normalny szum.

---

## Otwarte wątki nazewnictwa (do rozstrzygnięcia z Architektem)

- **NRI → PRI?** Koncepcja źródłowa nazywa kompozytowy indeks ryzyka "NEMEZIS Risk Index (NRI)". Kandydat na zmianę spójną z motywem: **PRI — Poseidon Risk Index**. To decyzja Architekta (indeks projektujesz Ty w Fazie 4–5, patrz `NEMEZIS_koncepcja.md` sekcja B3) — wracamy do tego przy definiowaniu kompozytu, nie zmieniam na siłę teraz.
