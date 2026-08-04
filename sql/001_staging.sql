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
    notice_id       TEXT NOT NULL,                -- numer ogloszenia TED/OJ S
    fetched_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_file     TEXT NOT NULL,                 -- nazwa paczki ZIP/XML pochodzenia, dla lineage
    eforms_version  TEXT,                          -- wersja schematu eForms, jesli rozpoznana
    raw_xml         TEXT NOT NULL,                 -- oryginalny XML 1:1, do audytu/debugowania
    payload         JSONB NOT NULL,                -- strukturalny XML->JSON, zero logiki biznesowej
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
