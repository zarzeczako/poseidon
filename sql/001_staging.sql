-- P.O.S.E.I.D.O.N. — Faza 1: warstwa staging
-- Strict ELT: surowe dane ladują tu bez ZADNEJ logiki biznesowej.
-- Python robi wylacznie Extract + Load (dla TED: plaski XML->JSON strukturalnie,
-- bez decyzji czyszczacych).

CREATE SCHEMA IF NOT EXISTS staging;

-- ============================================================
-- Tabele ladowania (immutable landing zone)
-- ============================================================

CREATE TABLE staging.bzp_notices_raw (
    id              BIGSERIAL PRIMARY KEY,
    notice_id       TEXT NOT NULL,               -- identyfikator ogloszenia w BZP
    fetched_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_endpoint TEXT NOT NULL,                -- wersja/endpoint API BZP, dla lineage
    payload         JSONB NOT NULL,               -- surowa odpowiedz API, nietknieta
    UNIQUE (notice_id, source_endpoint)
);

CREATE INDEX idx_bzp_notices_raw_payload_gin ON staging.bzp_notices_raw USING GIN (payload);
CREATE INDEX idx_bzp_notices_raw_notice_id ON staging.bzp_notices_raw (notice_id);

CREATE TABLE staging.ted_notices_raw (
    id              BIGSERIAL PRIMARY KEY,
    notice_id       TEXT NOT NULL,                -- numer ogloszenia TED (publication-number)
    fetched_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_file     TEXT NOT NULL,                 -- identyfikator zrodla (np. "Search API v3"), dla lineage
    eforms_version  TEXT,                          -- wersja schematu eForms, jesli rozpoznana
    -- raw_xml: NULL dla Search API v3 (zwraca JSON, nie XML). Pelny eForms XML mozna
    -- pobrac osobno przez payload->links->xml->MUL, jesli kiedys potrzebny -- nie
    -- pobierany domyslnie (dodatkowe zapytanie na kazde ogloszenie).
    raw_xml         TEXT,
    payload         JSONB NOT NULL,                -- odpowiedz Search API v3, nietknieta
    UNIQUE (notice_id)
);

CREATE INDEX idx_ted_notices_raw_payload_gin ON staging.ted_notices_raw USING GIN (payload);
CREATE INDEX idx_ted_notices_raw_notice_id ON staging.ted_notices_raw (notice_id);

-- ============================================================
-- Funkcje czyszczace -- NIP
-- ============================================================

-- Wyciaga same cyfry z identyfikatora (usuwa prefiks kraju typu 'PL', myslniki, spacje).
-- Zwraca NULL, jesli po wyczyszczeniu nie zostaje dokladnie 10 cyfr -- czyli to NIE jest
-- polski NIP (np. zagraniczny oferent w przetargu unijnym). Taki przypadek obsluzy
-- osobno warstwa entity resolution (Faza 3), nie ta funkcja.
CREATE OR REPLACE FUNCTION staging.clean_nip(raw_id TEXT)
RETURNS CHAR(10) AS $$
    SELECT CASE
        WHEN length(regexp_replace(coalesce(raw_id, ''), '\D', '', 'g')) = 10
            THEN regexp_replace(raw_id, '\D', '', 'g')::CHAR(10)
        ELSE NULL
    END
$$ LANGUAGE SQL IMMUTABLE;

-- Walidacja sumy kontrolnej polskiego NIP (wagi 6,5,7,2,3,4,5,6,7 na pierwszych 9 cyfrach,
-- suma mod 11 = 10-ta cyfra). Nieuzywana jeszcze w widokach ponizej -- to narzedzie
-- pod przyszle testy jakosci danych (pandera/Great Expectations, sekcja A3 koncepcji).
CREATE OR REPLACE FUNCTION staging.is_valid_nip(nip CHAR(10))
RETURNS BOOLEAN AS $$
    SELECT CASE
        WHEN nip !~ '^\d{10}$' THEN FALSE
        ELSE (
            6*substring(nip,1,1)::int + 5*substring(nip,2,1)::int + 7*substring(nip,3,1)::int +
            2*substring(nip,4,1)::int + 3*substring(nip,5,1)::int + 4*substring(nip,6,1)::int +
            5*substring(nip,7,1)::int + 6*substring(nip,8,1)::int + 7*substring(nip,9,1)::int
        ) % 11 = substring(nip,10,1)::int
    END
$$ LANGUAGE SQL IMMUTABLE;

-- ============================================================
-- Funkcje czyszczace -- REGON
-- Potrzebne jako fallback przy godzeniu BZP<->TED: TED miesza NIP i REGON w tym samym
-- polu (organisation-identifier-buyer), patrz recon/FINDINGS_TED.md Znalezisko 2.
-- Architekt zdecydowal (2026-08-04): najpierw probowac NIP, REGON tylko jako fallback.
-- ============================================================

-- Jak clean_nip, ale dla REGON-9 (krotka forma, 9 cyfr). REGON-14 (jednostki lokalne
-- wiekszych podmiotow) nie jest tu obslugiwany -- nie zaobserwowany jeszcze w probkach.
CREATE OR REPLACE FUNCTION staging.clean_regon(raw_id TEXT)
RETURNS CHAR(9) AS $$
    SELECT CASE
        WHEN length(regexp_replace(coalesce(raw_id, ''), '\D', '', 'g')) = 9
            THEN regexp_replace(raw_id, '\D', '', 'g')::CHAR(9)
        ELSE NULL
    END
$$ LANGUAGE SQL IMMUTABLE;

-- Walidacja sumy kontrolnej REGON-9 (wagi 8,9,2,3,4,5,6,7 na pierwszych 8 cyfrach,
-- suma mod 11; jesli wynik = 10, kontrolna cyfra to 0).
CREATE OR REPLACE FUNCTION staging.is_valid_regon(regon CHAR(9))
RETURNS BOOLEAN AS $$
    SELECT CASE
        WHEN regon !~ '^\d{9}$' THEN FALSE
        ELSE (
            CASE WHEN (
                8*substring(regon,1,1)::int + 9*substring(regon,2,1)::int + 2*substring(regon,3,1)::int +
                3*substring(regon,4,1)::int + 4*substring(regon,5,1)::int + 5*substring(regon,6,1)::int +
                6*substring(regon,7,1)::int + 7*substring(regon,8,1)::int
            ) % 11 = 10 THEN 0
            ELSE (
                8*substring(regon,1,1)::int + 9*substring(regon,2,1)::int + 2*substring(regon,3,1)::int +
                3*substring(regon,4,1)::int + 4*substring(regon,5,1)::int + 5*substring(regon,6,1)::int +
                6*substring(regon,7,1)::int + 7*substring(regon,8,1)::int
            ) % 11
            END
        ) = substring(regon,9,1)::int
    END
$$ LANGUAGE SQL IMMUTABLE;
