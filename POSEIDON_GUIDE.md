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

---

## Otwarte wątki nazewnictwa (do rozstrzygnięcia z Architektem)

- **NRI → PRI?** Koncepcja źródłowa nazywa kompozytowy indeks ryzyka "NEMEZIS Risk Index (NRI)". Kandydat na zmianę spójną z motywem: **PRI — Poseidon Risk Index**. To decyzja Architekta (indeks projektujesz Ty w Fazie 4–5, patrz `NEMEZIS_koncepcja.md` sekcja B3) — wracamy do tego przy definiowaniu kompozytu, nie zmieniam na siłę teraz.
