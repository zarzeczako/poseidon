# Rekonesans BZP API — pierwsze ustalenia (2026-08-03)

Próbka: 3x TenderResultNotice + 3x ContractNotice, lipiec 2026. Surowe pliki obok tego dokumentu:
`bzp_sample_tenderresult.json`, `bzp_sample_contractnotice.json`, `bzp_glossary_noticetype.json`.

To jest PIERWSZY przebieg (mały, celowo) — nie pełny rekonesans z roadmapy (5000 ogłoszeń). Cel: dać Ci
realne dane do obejrzenia, nie skończyć za Ciebie decyzję o ziarnie/mapowaniu pól.

## Endpoint (potwierdzone: działa, bez autoryzacji)

```
GET https://ezamowienia.gov.pl/mo-board/api/v1/notice
    ?PageSize=...&NoticeType=...&PublicationDateFrom=YYYY-MM-DD&PublicationDateTo=YYYY-MM-DD
```

Uwaga: `mo-client-board/api/notices/` (adres z koncepcji) to frontend Angular (SPA), nie API. Prawdziwy
backend to `mo-board/api/v1/notice`. Odkryte przez podgląd ruchu sieciowego prawdziwej wyszukiwarki na
stronie, nie przez zgadywanie.

## Glosariusz NoticeType

Pełna lista 37 wartości w `bzp_glossary_noticetype.json` (endpoint: `mo-board/api/v1/glossary?glossaryType=noticeType`).
Kluczowe dla nas: `ContractNotice`, `TenderResultNotice`, `ContractPerformingNotice`, `TenderPlanNotice` —
plus warianty `...EU` (`ContractNoticeEU`, `ContractAwardNoticeEU` itd.) dla postępowań unijnych
publikowanych też na BZP.

## Znalezisko 1 — mamy bezpośrednią flagę progu UE, nie trzeba jej zgadywać

Pole `isTenderAmountBelowEU: bool` jest wprost w rekordzie. To zmienia warstwę godzenia BZP<->TED:
zamiast zgadywać/wyliczać, które BZP szukają pary w TED, filtrujemy `isTenderAmountBelowEU = false` —
twarda odpowiedź z samego źródła, nie heurystyka.

## Znalezisko 2 — ziarno "1 część postępowania" potwierdzone empirycznie, ale reprezentacja jest brzydka

Rekord wieloczęściowy (`bzpNumber: 2026/BZP 00315919`) ma:
- `procedureResult: "zawarcieUmowy;uniewaznienie;zawarcieUmowy"` — 3 wyniki, rozdzielone średnikiem
- `contractors`: tablica 3 obiektów, POZYCYJNIE zgodna z `procedureResult` (środkowy, dla unieważnionej
  części, ma same nulle)

To potwierdza pierwotną decyzję z koncepcji o ziarnie (`F_Postepowania` = 1 część), ale znaczy, że trzeba
te równoległe listy rozpakować pozycyjnie (unnest) — nie da się tego zmapować 1:1 JSON-rekord -> wiersz.

**Pułapka:** gdy jest tylko 1 część, `contractors` NIE jest tablicą jednoelementową — jest gołym obiektem
(`{...}`, nie `[{...}]`). Kod zakładający zawsze tablicę wywali się albo cicho zwróci złe dane na
postępowaniach jednoczęściowych. Sprawdzone na 3 różnych rekordach (1, 2 i 3 części).

## Znalezisko 3 — liczba ofert i cena wygranej NIE są polami strukturalnymi

Pełna lista pól obiektu (sprawdzona programowo, nie z urwanego podglądu): `clientType`, `orderType`,
`tenderType`, `noticeType`, `noticeNumber`, `bzpNumber`, `isTenderAmountBelowEU`, `publicationDate`,
`orderObject`, `cpvCode`, `submittingOffersDate`, `procedureResult`, `organizationName/City/Province/
Country/NationalId/Id`, `tenderId`, `htmlBody`, `contractors`, `objectId`. Żadne z nich nie niesie wprost
liczby złożonych ofert ani ceny wybranej oferty.

Potwierdzone: fraza "najkorzystniejsz*" (jak w "oferta najkorzystniejsza") występuje w `htmlBody` — te
dane najpewniej trzeba wyciągnąć z renderowanego HTML ogłoszenia, nie z czystego JSON. To jest OTWARTE:
nie sprawdziłem, czy istnieje osobny endpoint "szczegóły ogłoszenia" z czystszymi polami — spróbowałem
kilku zgadywanych ścieżek (`/notice/{bzpNumber}`, `/tender/{tenderId}`), żadna nie zadziałała (404).

**To jest największe ryzyko dla całego projektu.** F1_JednaOferta i F4_CenaVsSzacunek to serce
NRI/PRI — jeśli trzeba je parsować z HTML zamiast czytać z JSON, to podnosi trudność Fazy 1 podobnie do
"najbrudniejszej roboty" z eForms opisanej w koncepcji dla TED — tylko że teraz też po stronie BZP.

## ROZWIĄZANIE Znalezisko 3 (2026-08-04) — dane SĄ dostępne, i to bez ryzyka "niedbałego HTML"

Znalazłem prawdziwą stronę szczegółów ogłoszenia w UI (`/mo-client-board/bzp/notice-details/id/{guid}`,
GUID inny niż `objectId` z listy — trzeba było kliknąć prawdziwy link w przeglądarce, nie zgadywać) i
podejrzałem, co faktycznie renderuje się na ekranie dla `TenderResultNotice` (2026/BZP 00377115).

**Liczba ofert i cena SĄ w `htmlBody`** (dokładnie to samo pole, które już mamy w próbce) — ale to NIE
jest dowolny, niedbały HTML. To renderowany, **znormalizowany prawnie formularz** z Rozporządzenia
o ogłoszeniach, ze stałymi, numerowanymi kodami pól, identycznymi w każdym ogłoszeniu tego typu:

```
SEKCJA VI OFERTY (dla części 1)
6.1.) Liczba otrzymanych ofert lub wniosków: 6
6.1.1.) Liczba otrzymanych ofert wariantowych: 0
6.2.) Cena lub koszt oferty z najniższą ceną lub kosztem: 51660 PLN
6.3.) Cena lub koszt oferty z najwyższą ceną lub kosztem: 108052,62 PLN
6.4.) Cena lub koszt oferty wykonawcy, któremu udzielono zamówienia: 51660 PLN
```

Potwierdzone: dokładnie ten sam wzorzec (`6.1.) Liczba otrzymanych ofert`, `6.2.) Cena`, `6.4.) Cena`)
występuje też we WSZYSTKICH 3 rekordach z oryginalnej próbki `bzp_sample_tenderresult.json` — to nie
jest przypadek jednego ogłoszenia, tylko stały wzorzec formularza. Sekcje VI-VIII powtarzają się
identycznie per `Część N`, więc parsowanie = podziel po granicach "Część N", potem regex po stałym
kodzie pola (`6\.1\.\)\s*Liczba otrzymanych ofert[^:]*:\s*(\d+)` itd.) w obrębie każdego bloku.

To NIE jest to samo ryzyko co "sparsuj dowolną stronę WWW" — to parsowanie ustandaryzowanego,
prawnie narzuconego formularza z sekcjami numerowanymi jak w ustawie. Ryzyko, które zostaje: wersjonowanie
szablonu w czasie (widziałem w aktualnościach portalu wzmiankę o zmianach formularza w 2026-05), więc
parser musi być odporny na drobne zmiany numeracji/etykiet między latami 2021-2026, i powinien
walidować wyciągnięte wartości (np. liczba ofert musi się sparsować jako mała nieujemna liczba całkowita
— jeśli nie, rekord leci do przeglądu, nie wchodzi cicho jako śmieciowa wartość).

**Bonus:** przy okazji klikania w UI złapałem realny endpoint wyszukiwania używany przez samą aplikację:
`Board/Search?publicationDateFrom=...&SortingColumnName=PublicationDate&SortingDirection=DESC&PageNumber=1&PageSize=10`
— to odpowiada na wcześniejsze pytanie o mechanizm paginacji (`PageNumber`/`PageSize`, sortowanie jawne).

## Znalezisko 4 — realny przypadek brzegowy dla czyszczenia NIP

`contractorNationalId` bywa: `"brak - podmiot nie prowadzący działaności gospodarczej"` (zwycięzca to
osoba fizyczna bez działalności gospodarczej, brak NIP). `staging.clean_nip()` już to poprawnie obsłuży
(zwróci NULL, bo to nie 10 cyfr) — ale warto rozważyć osobną flagę `czy_osoba_fizyczna` zamiast po
prostu gubić ten przypadek jako "brak danych", bo to co innego niż błąd/brak w danych źródłowych.

## Nieprzebadane w tym przebiegu

- TED w ogóle nietknięty (3 sierpnia była zresztą zaplanowana przerwa techniczna w dostępie do TED,
  7:00-8:00 — widoczne w komunikatach na stronie głównej e-Zamówienia)
- Pozostałe ~33 wartości NoticeType z glosariusza
- Realny mechanizm paginacji przy dużych zakresach dat (czy jest `totalCount`/nagłówek z liczbą stron?) —
  próbka miała tylko PageSize=3, bez testu stronicowania
- Czy istnieje endpoint "szczegóły pojedynczego ogłoszenia" bogatszy niż lista

## Sugerowany następny krok (Twój, ręcznie)

Otwórz `bzp_sample_tenderresult.json` w edytorze, znajdź w `htmlBody` sekcję z liczbą ofert/ceną
(szukaj "najkorzystniejsz" albo "LICZBA OTRZYMANYCH OFERT") i zobacz, czy da się to wyciągnąć
regexem/parserem HTML wiarygodnie na wielu wariantach formularza, czy to zbyt kruche. To bezpośrednio
decyduje, jak trudna będzie Faza 1 po stronie BZP — i czy w ogóle warto próbować, czy szukać innego
źródła dla tych dwóch pól.
