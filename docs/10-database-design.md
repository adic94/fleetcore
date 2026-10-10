# Projekt bazy danych

PostgreSQL 16. Jedna baza, schematy odwzorowujące moduły. Diagramy: [ERD](11-postgresql-erd-diagrams.md).

> **Bloki SQL są ułożone tematycznie, nie w kolejności wykonania.** Migracje tworzą obiekty w kolejności zależności: rozszerzenia i role → `core` → `docs` → `fleet` → `tax` → `fin` → `assets`, `telematics`, `rent`, `tms` → `integr`, `audit` → polityki RLS → widoki. Definicje tutaj są projektem do przeniesienia do `db/migrations/`, a bramka `migration-apply` dowodzi, że przechodzą na czystej bazie.

## Konwencje obowiązujące wszędzie

1. Klucz główny: `id BIGINT GENERATED ALWAYS AS IDENTITY`. Klucze naturalne (VIN, NIP) mają własne ograniczenia unikalności, ale nie są kluczem głównym — zmieniają się rzadziej niż numer rejestracyjny, ale jednak się zmieniają (korekta literówki w VIN to realny przypadek).
2. Każda tabela danych klienta ma `company_id BIGINT NOT NULL REFERENCES core.companies(id)` i politykę RLS. Bez wyjątków — jedyne tabele z `company_id` dopuszczającym `NULL` (słowniki systemowe, audyt, surowe odpowiedzi) mają jawnie opisaną regułę w rozdziale o RLS.
3. Kwoty: `NUMERIC(14,2)`. **Nigdy** typ zmiennoprzecinkowy.
4. Waluta: `CHAR(3)` obok każdej kwoty, która może nie być w złotych.
5. Czas: `TIMESTAMPTZ`. Daty zdarzeń urzędowych (rejestracja, deklaracja): `DATE`.
6. Miary: `NUMERIC` z jawną jednostką w nazwie kolumny (`dmc_kg`, `mileage_km`, `volume_l`).
7. Audyt: `created_at`, `created_by`, `updated_at`, `updated_by` w każdej tabeli edytowalnej.
8. Usuwanie: `deleted_at` (miękkie) dla danych, do których odwołują się dokumenty. Twarde usuwanie tylko dla słowników bez powiązań.
9. **Klucz obcy między tabelami najemcy zawiera `company_id`.** Każda tabela najemcy ma dodatkowo `UNIQUE (company_id, id)`, a odwołanie do niej to `FOREIGN KEY (company_id, x_id) REFERENCES schema.tabela (company_id, id)`. Sam `REFERENCES tabela(id)` pozwala wierszowi spółki A wskazać oddział, MPK czy pojazd spółki B — RLS sprawdza wiersz, który czytamy, a nie wiersz, na który on wskazuje. Poniższe definicje pokazują wzorzec na tabelach `core` i `fleet.vehicles`; migracje stosują go do **każdej** relacji między tabelami najemcy.
10. Unikalność z kolumną, która może być `NULL`, zapisujemy jako `UNIQUE NULLS NOT DISTINCT` (PostgreSQL 15+). Zwykłe `UNIQUE` traktuje każde `NULL` jako różne i przepuszcza duplikaty.

### Wymagania wstępne bazy

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- ograniczenia EXCLUDE z równością na BIGINT
CREATE EXTENSION IF NOT EXISTS pgcrypto;     -- gen_random_bytes, digest

-- Role (hasła z magazynu sekretów, nie z repozytorium)
CREATE ROLE fleetcore_owner NOLOGIN;                         -- właściciel schematów i tabel
CREATE ROLE fleetcore_migrator LOGIN IN ROLE fleetcore_owner; -- uruchamia migracje
CREATE ROLE fleetcore_app   LOGIN NOBYPASSRLS NOSUPERUSER;   -- API i worker
CREATE ROLE fleetcore_maint LOGIN BYPASSRLS  NOSUPERUSER;    -- WYŁĄCZNIE zadania worker:
                                                             -- odświeżanie widoków, retencja

-- Uprawnienia per schemat; app nie dostaje nic z automatu
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA core, fleet, tax, fin, rent, tms, assets, telematics, docs, integr, audit
  TO fleetcore_app, fleetcore_maint;
-- SELECT/INSERT/UPDATE/DELETE nadawane tabela po tabeli w migracji, która ją tworzy.
-- ZAKAZ: GRANT ... ON ALL TABLES IN SCHEMA — obejmuje też widoki materializowane
-- i po cichu otwiera aplikacji fleet.mv_vehicle_tco (sprawdzone na PostgreSQL 16).
-- Bramka tenant-isolation sprawdza w katalogu, że fleetcore_app nie ma uprawnień
-- do żadnego widoku materializowanego.

-- Rola konserwacyjna czyta źródła widoków materializowanych:
GRANT SELECT ON fleet.events TO fleetcore_maint;
-- audit.audit_logs: fleetcore_app ma INSERT i SELECT (pod RLS), bez UPDATE/DELETE.
```

Tabele i widoki należą do `fleetcore_owner`, **poza widokami materializowanymi**, które należą do `fleetcore_maint` — `REFRESH` wymaga własności, a właściciel z `FORCE ROW LEVEL SECURITY` na tabelach źródłowych nie widziałby wszystkich spółek.

## Zasada, która wynika z doświadczenia, nie z podręcznika

**Brak danych to `NULL`, nie `0` i nie pusty łańcuch.**

Źródła zewnętrzne zapisują nieznane DMC jako zero. Potraktowanie zera jako wartości dało 28 z 43 fałszywych „konfliktów podatkowych", w których ginął prawdziwy sygnał. Import ma obowiązek zamienić zero na `NULL` dla pól, gdzie zero nie jest sensowną wartością — a ograniczenie `CHECK` w bazie tego pilnuje.

Tam, gdzie zero **jest** sensowne (np. kwota 0 zł, stan licznika 0 km w nowym pojeździe, 0 punktów karnych), fallback w kodzie używa operatora obsługującego wyłącznie `NULL`, nie operatora logicznego — inaczej zero zostanie podmienione na wartość zapasową.

---

## Schemat `core`

```sql
CREATE TABLE core.companies (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code           TEXT NOT NULL UNIQUE,          -- krótki identyfikator spółki
  name           TEXT NOT NULL,
  nip            TEXT,
  regon          TEXT,
  street         TEXT,                          -- adres siedziby wprost w tabeli:
  postal_code    TEXT,                          -- spółka powstaje przed swoimi adresami,
  city           TEXT,                          -- więc nie wskazuje na core.addresses
  teryt          TEXT,                          -- gmina siedziby: właściwość dla DT-1
  lifecycle      TEXT NOT NULL DEFAULT 'onboarding'
                   CHECK (lifecycle IN ('onboarding','active','offboarding','closed')),
                                                -- 'onboarding': wolno czyścić dane importowe
                                                -- i wczytywać ponownie; po odbiorze danych 'active'.
                                                -- Trigger: z 'active' nie da się wrócić do 'onboarding'.
                                                -- Zasady czyszczenia: docs/14-onboarding-klienta.md
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE core.users (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email          TEXT NOT NULL UNIQUE,
  password_hash  TEXT,
  external_sub   TEXT UNIQUE,                   -- identyfikator z dostawcy OIDC
  full_name      TEXT NOT NULL,
  platform_role  TEXT NOT NULL DEFAULT 'user'
                   CHECK (platform_role IN ('superadmin','user')),  -- superadmin: technika, BEZ danych klientów
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  mfa_enabled    BOOLEAN NOT NULL DEFAULT FALSE,
  mfa_secret_ref TEXT,                          -- odwołanie do magazynu sekretów, nie sam sekret
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Dostęp do spółki jest WIERSZEM, nie właściwością roli.
-- Rola jest per spółka: ta sama osoba może być księgową w jednej spółce i przeglądającym w drugiej.
-- „Operator wielospółkowy" to po prostu użytkownik z wieloma wierszami tutaj.
CREATE TABLE core.user_company_access (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id        BIGINT NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  role           TEXT NOT NULL CHECK (role IN
                   ('admin','manager','dispatcher','accountant','driver','viewer')),
  can_view_routes BOOLEAN NOT NULL DEFAULT FALSE,   -- dostęp do surowych tras GPS; każde użycie w audycie
  is_implementer BOOLEAN NOT NULL DEFAULT FALSE,    -- nasz wdrożeniowiec: może czyścić dane w statusie 'onboarding';
                                                    -- nadanie odbierane po zakończeniu opieki powdrożeniowej
  granted_by     BIGINT REFERENCES core.users(id),
  granted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, company_id)
);

CREATE TABLE core.addresses (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  street         TEXT,
  postal_code    TEXT,
  city           TEXT NOT NULL,
  country        CHAR(2) NOT NULL DEFAULT 'PL',
  lat            NUMERIC(9,6),
  lon            NUMERIC(9,6),
  UNIQUE (company_id, id)
);

CREATE TABLE core.branches (              -- oddziały
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  code           TEXT NOT NULL,
  name           TEXT NOT NULL,
  address_id     BIGINT,
  UNIQUE (company_id, code),
  UNIQUE (company_id, id),
  FOREIGN KEY (company_id, address_id) REFERENCES core.addresses (company_id, id)
);

CREATE TABLE core.cost_centers (          -- MPK
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  code           TEXT NOT NULL,
  name           TEXT NOT NULL,
  parent_id      BIGINT,
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (company_id, code),
  UNIQUE (company_id, id),
  FOREIGN KEY (company_id, parent_id) REFERENCES core.cost_centers (company_id, id)
);

CREATE TABLE core.partners (              -- kontrahenci: dostawcy, klienci, ubezpieczyciele
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  name           TEXT NOT NULL,
  nip            TEXT,
  kind           TEXT[] NOT NULL,               -- {'supplier','customer','insurer','leasing'}
  address_id     BIGINT,
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (company_id, id),
  FOREIGN KEY (company_id, address_id) REFERENCES core.addresses (company_id, id)
);

CREATE TABLE core.employees (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  user_id        BIGINT REFERENCES core.users(id),   -- nie każdy pracownik ma konto
  first_name     TEXT NOT NULL,
  last_name      TEXT NOT NULL,
  personal_no    TEXT,                          -- numer kadrowy, NIE PESEL
  branch_id      BIGINT,
  cost_center_id BIGINT,
  hired_on       DATE,
  left_on        DATE,
  deleted_at     TIMESTAMPTZ,
  UNIQUE (company_id, id),
  FOREIGN KEY (company_id, branch_id)      REFERENCES core.branches (company_id, id),
  FOREIGN KEY (company_id, cost_center_id) REFERENCES core.cost_centers (company_id, id)
);

CREATE TABLE core.dictionaries (          -- słowniki definiowane przez użytkownika
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT REFERENCES core.companies(id),  -- NULL = słownik systemowy
  kind           TEXT NOT NULL,                 -- 'fuel_type','vehicle_kind','damage_type',...
  code           TEXT NOT NULL,
  label          TEXT NOT NULL,
  sort_order     INT NOT NULL DEFAULT 0,
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE NULLS NOT DISTINCT (company_id, kind, code)   -- bez tego słownik systemowy przyjmie duplikat
);

-- Definicje pól rozszerzalnych kartoteki (kolumna fleet.vehicles.extra)
CREATE TABLE core.field_definitions (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  entity         TEXT NOT NULL CHECK (entity IN ('vehicle','employee','contract','policy')),
  key            TEXT NOT NULL CHECK (key ~ '^[a-z][a-z0-9_]{1,62}$'),  -- klucz w JSONB
  label          TEXT NOT NULL,
  data_type      TEXT NOT NULL CHECK (data_type IN ('text','number','date','bool','dictionary')),
  dictionary_kind TEXT,                         -- dla data_type = 'dictionary'
  in_grid        BOOLEAN NOT NULL DEFAULT TRUE,
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (company_id, entity, key)
);

-- Definicje raportów i widoków siatek: żyją w bazie, nie na stacji roboczej
CREATE TABLE core.report_definitions (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  user_id        BIGINT REFERENCES core.users(id),   -- NULL = definicja wspólna dla spółki
  code           TEXT NOT NULL,                      -- np. 'vehicles', 'fuel_card_limits'
  name           TEXT NOT NULL,
  columns        JSONB NOT NULL,                     -- nazwy logiczne z mapy wyrażeń, nie SQL
  filters        JSONB NOT NULL DEFAULT '{}',
  sort           JSONB NOT NULL DEFAULT '[]',
  group_by       JSONB NOT NULL DEFAULT '[]',
  UNIQUE NULLS NOT DISTINCT (company_id, user_id, code)
);
```

`report_definitions.columns` zawiera wyłącznie **nazwy logiczne** z mapy wyrażeń w kodzie, nigdy surowy SQL — bramka `report-columns` sprawdza, że każda nazwa ma wpis w mapie, a wyrażenie odwołuje się do istniejących kolumn ([model danych](05-data-model-and-analytics.md)).

> **`core.dictionaries` rozstrzyga jeden spór z góry.** Statusy o znaczeniu procesowym (status rezerwacji, status deklaracji) **nie** trafiają tutaj — siedzą w ograniczeniu `CHECK` przy swojej tabeli. Powód: gdy słownik statusów można edytować z interfejsu, a kod zna tylko część wartości, powstaje stan, w którym zapis łamie ograniczenie albo interfejs pokazuje surową wartość techniczną zamiast etykiety. Oba objawy zdarzyły się w systemie odniesienia.

### Licencjonowanie modułów

Wzorzec przejęty z PasCom, który sprzedaje moduły podstawowe, dodatkowe i pakiety łączące produkty. Klient chcący samą ewidencję pojazdów nie powinien płacić za spedycję kontenerową.

```sql
CREATE TABLE core.company_modules (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  module_code    TEXT NOT NULL,            -- 'fleet','rent','tms','fin','tax','assets','telematics'
  enabled        BOOLEAN NOT NULL DEFAULT TRUE,
  valid_from     DATE NOT NULL DEFAULT CURRENT_DATE,
  valid_to       DATE,
  granted_by     BIGINT REFERENCES core.users(id),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, module_code)
);
```

> **Kolejność wdrożenia jest tu ważniejsza niż sam schemat.** W systemie odniesienia odpowiednik tej tabeli powstał, ale odczyt i zapis celują w **dwie niezgodne struktury** — jedna ścieżka wymaga kolumny, której druga nie zna. Skutek: firma bez wiersza dostaje pełny dostęp, więc administrator może zapisać pakiet podstawowy i **nie stanie się nic**, cicho.
>
> Właściwa kolejność: utworzyć tabelę → ustawić wyłącznik awaryjny (`MODULE_ENFORCEMENT=off`) → dopiero wtedy wstawiać wiersze → włączyć egzekwowanie świadomie. Brak wiersza musi oznaczać **pełny dostęp**, nie brak dostępu — inaczej pierwsza migracja odcina wszystkich klientów.

---

## Schemat `fleet`

### Pojazd

```sql
CREATE TABLE fleet.vehicles (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id         BIGINT NOT NULL REFERENCES core.companies(id),
  vin                TEXT,                      -- tożsamość pojazdu
  plate              TEXT NOT NULL,             -- BIEŻĄCY numer, kopia utrzymywana przez trigger
                                                -- z vehicle_plates (źródło prawdy); nie edytowany wprost
  brand              TEXT,
  model              TEXT,
  kind               TEXT,                      -- ciężarowy, osobowy, przyczepa, specjalny...
  homolog_category   TEXT,                      -- M1, N1, N2, N3, O1..O4
  homolog_no         TEXT,
  production_year    INT CHECK (production_year BETWEEN 1900 AND 2100),
  first_reg_date     DATE,

  -- pola podatkowe: osobny reżim zmian, patrz vehicle_field_provenance
  dmc_kg             NUMERIC(10,2) CHECK (dmc_kg > 0),
  curb_weight_kg     NUMERIC(10,2) CHECK (curb_weight_kg > 0),
  combo_dmc_kg       NUMERIC(10,2) CHECK (combo_dmc_kg > 0),
  axles_count        SMALLINT CHECK (axles_count BETWEEN 1 AND 10),
  suspension_type    TEXT CHECK (suspension_type IN ('pneumatic','other')),
                                                -- 'pneumatic' = pneumatyczne LUB uznane za równoważne
  engine_cc          INT CHECK (engine_cc > 0),
  power_kw           NUMERIC(7,2) CHECK (power_kw > 0),
  fuel_type          TEXT,
  euro_standard      TEXT,
  seats              SMALLINT CHECK (seats > 0),

  branch_id          BIGINT,                    -- BIEŻĄCE przypisanie; historia w vehicle_assignments
  cost_center_id     BIGINT,
  status             TEXT NOT NULL DEFAULT 'active'
                       CHECK (status IN ('active','sold','scrapped','reserve','leased_out')),
  acquired_on        DATE,
  disposed_on        DATE,
  extra              JSONB NOT NULL DEFAULT '{}',   -- pola rozszerzalne, definicje w core.field_definitions
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at         TIMESTAMPTZ,
  UNIQUE (company_id, id),
  FOREIGN KEY (company_id, branch_id)      REFERENCES core.branches (company_id, id),
  FOREIGN KEY (company_id, cost_center_id) REFERENCES core.cost_centers (company_id, id)
);

CREATE UNIQUE INDEX uq_vehicles_vin
  ON fleet.vehicles (company_id, vin) WHERE vin IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX ix_vehicles_plate ON fleet.vehicles (company_id, plate);
CREATE INDEX ix_vehicles_extra ON fleet.vehicles USING GIN (extra);
```

**Dlaczego `axles_count` i `suspension_type` nie mają wartości domyślnej.** Od 12 t stawka podatku zależy od liczby osi i rodzaju zawieszenia. Wartość domyślna oznacza najniższą stawkę w przedziale i deklarację, która wygląda poprawnie. Na próbce 24 pojazdów pięć miało zaniżoną kategorię wyłącznie z tego powodu. `NULL` ma dawać status „nie da się ustalić" — widoczny błąd zamiast cichego zaniżenia.

**Dlaczego `plate` nie jest unikalne, a `vin` jest.** Numer rejestracyjny zmienia się przy przerejestrowaniu. Scalanie po numerze dało 26 pojazdów pod więcej niż jedną tablicą (53 wiersze zamiast 26) i zawyżyło sumę podatku o kilkanaście tysięcy złotych.

```sql
CREATE TABLE fleet.vehicle_plates (       -- historia numerów rejestracyjnych
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id    BIGINT NOT NULL,
  plate         TEXT NOT NULL,
  valid_from    DATE NOT NULL,
  valid_to      DATE,
  document_id   BIGINT,
  EXCLUDE USING gist (vehicle_id WITH =, daterange(valid_from, valid_to) WITH &&),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id) ON DELETE CASCADE,
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id)
);

-- Skąd pochodzi każde pole podatkowe i jaką ma rangę.
CREATE TABLE fleet.vehicle_field_provenance (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id    BIGINT NOT NULL,
  field_name    TEXT NOT NULL,
  value_text    TEXT,
  source        TEXT NOT NULL CHECK (source IN
                  ('manual','registration_doc','erp','fleet_platform','fuel_import','cep')),
  rank          SMALLINT NOT NULL,
  document_id   BIGINT,
  confidence    NUMERIC(4,3),
  recorded_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (vehicle_id, field_name, source),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id) ON DELETE CASCADE,
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id)
);
```

```sql
-- Ranga źródła jest konfiguracją najemcy, nie stałą w kodzie.
CREATE TABLE core.source_ranks (
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  source         TEXT NOT NULL CHECK (source IN
                   ('manual','registration_doc','erp','fleet_platform','fuel_import','cep')),
  rank           SMALLINT NOT NULL CHECK (rank BETWEEN 1 AND 9),
  system_name    TEXT,                    -- np. 'ZSI', 'MyCar', 'ORLEN Flota' — dla raportów
  PRIMARY KEY (company_id, source)
);
```

`vehicle_field_provenance` to tabela, której nie ma żaden z zastępowanych programów, i jedyna odpowiedź na pytanie „skąd wiemy, że ten pojazd ma 4 osie". Rozstrzyganie konfliktu: wygrywa najwyższa ranga; przy remisie — najnowszy zapis; przy sprzeczności między źródłami tej samej rangi — wpis trafia na listę do rozstrzygnięcia przez człowieka, a pole zostaje `NULL`.

### Zdarzenia

```sql
CREATE TABLE fleet.events (
  id            BIGINT GENERATED ALWAYS AS IDENTITY,
  company_id    BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id    BIGINT,
  employee_id   BIGINT,
  kind          TEXT NOT NULL CHECK (kind IN
                  ('refuel','service','repair','inspection','damage','fine','lease_payment',
                   'insurance','odometer','handover','return','trip','assignment','toll','other')),
  occurred_at   TIMESTAMPTZ NOT NULL,
  amount_net    NUMERIC(14,2),
  amount_gross  NUMERIC(14,2),
  vat_amount    NUMERIC(14,2),
  currency      CHAR(3) NOT NULL DEFAULT 'PLN',
  document_id   BIGINT,
  source        TEXT NOT NULL,             -- 'manual','fuel_import','telematics','ocr','api'
  external_ref  TEXT,                      -- identyfikator u źródła, do deduplikacji
  payload       JSONB NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by    BIGINT REFERENCES core.users(id),
  PRIMARY KEY (id, occurred_at),
  UNIQUE (company_id, id, occurred_at),     -- cel kluczy obcych z fin.*
  FOREIGN KEY (company_id, vehicle_id)  REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, employee_id) REFERENCES core.employees (company_id, id),
  CHECK (vehicle_id IS NOT NULL OR employee_id IS NOT NULL),
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id)
) PARTITION BY RANGE (occurred_at);

CREATE INDEX ix_events_vehicle ON fleet.events (company_id, vehicle_id, occurred_at DESC);

-- Deduplikacja importów: osobna, NIEpartycjonowana tabela kluczy źródłowych.
CREATE TABLE fleet.event_source_keys (
  company_id    BIGINT NOT NULL REFERENCES core.companies(id),
  source        TEXT NOT NULL,
  external_ref  TEXT NOT NULL,
  event_id      BIGINT NOT NULL,
  occurred_at   TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (company_id, source, external_ref),
  FOREIGN KEY (company_id, event_id, occurred_at)
    REFERENCES fleet.events (company_id, id, occurred_at) ON DELETE CASCADE
);
```

`fleet.event_source_keys` to zabezpieczenie przed podwójnym importem tego samego pliku kart paliwowych — najczęstszy błąd obsługi, jaki widać w danych. Klucz siedzi w osobnej tabeli, bo indeks unikalny na tabeli partycjonowanej **musi zawierać klucz partycji**: `(company_id, source, external_ref, occurred_at)` przepuściłby ten sam rekord wczytany ponownie z poprawioną godziną albo strefą czasową. Import wstawia zdarzenie i klucz w jednej transakcji; konflikt na kluczu = duplikat.

### Rejestry towarzyszące

```sql
CREATE TABLE fleet.contracts (            -- leasing, najem, kredyt, umowy z dostawcami
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT,
  partner_id     BIGINT NOT NULL,
  kind           TEXT NOT NULL CHECK (kind IN ('lease','rental','credit','service','purchase')),
  number         TEXT NOT NULL,
  start_date     DATE NOT NULL,
  end_date       DATE,
  mileage_limit  INT,                      -- do kontroli nadprzebiegu
  value_net      NUMERIC(14,2),
  currency       CHAR(3) NOT NULL DEFAULT 'PLN',
  document_id    BIGINT,
  UNIQUE (company_id, partner_id, number),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, partner_id) REFERENCES core.partners (company_id, id),
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id),
  UNIQUE (company_id, id)
);

CREATE TABLE fleet.contract_schedule (    -- harmonogram rat
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  contract_id    BIGINT NOT NULL,
  seq            INT NOT NULL,
  due_date       DATE NOT NULL,
  capital_net    NUMERIC(14,2),
  interest_net   NUMERIC(14,2),
  total_gross    NUMERIC(14,2) NOT NULL,
  paid_on        DATE,
  UNIQUE (contract_id, seq),
  FOREIGN KEY (company_id, contract_id) REFERENCES fleet.contracts (company_id, id) ON DELETE CASCADE
);

CREATE TABLE fleet.policies (             -- polisy
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT NOT NULL,
  insurer_id     BIGINT NOT NULL,
  number         TEXT NOT NULL,
  scope          TEXT[] NOT NULL,               -- {'OC','AC','NNW','GAP','ASS'}
  valid_from     DATE NOT NULL,
  valid_to       DATE NOT NULL,
  premium_gross  NUMERIC(14,2),
  installments   SMALLINT DEFAULT 1,
  deductible     NUMERIC(14,2),
  document_id    BIGINT,
  CHECK (valid_to > valid_from),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, insurer_id) REFERENCES core.partners (company_id, id),
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id),
  UNIQUE (company_id, id)
);
CREATE INDEX ix_policies_expiry ON fleet.policies (company_id, valid_to);

CREATE TABLE fleet.damages (              -- szkody
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT NOT NULL,
  driver_id      BIGINT,
  policy_id      BIGINT,
  occurred_at    TIMESTAMPTZ NOT NULL,
  reported_at    TIMESTAMPTZ,
  claim_no       TEXT,
  fault          TEXT CHECK (fault IN ('own','third_party','unknown')),
  status         TEXT NOT NULL DEFAULT 'reported'
                   CHECK (status IN ('reported','assessed','repair','closed','rejected')),
  estimate_net   NUMERIC(14,2),
  payout_net     NUMERIC(14,2),
  own_share      NUMERIC(14,2),
  description    TEXT,
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, driver_id) REFERENCES core.employees (company_id, id),
  FOREIGN KEY (company_id, policy_id) REFERENCES fleet.policies (company_id, id),
  UNIQUE (company_id, id)
);

CREATE TABLE fleet.odometer_readings (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT NOT NULL,
  read_at        TIMESTAMPTZ NOT NULL,
  mileage_km     INT NOT NULL CHECK (mileage_km >= 0),
  source         TEXT NOT NULL CHECK (source IN
                   ('manual','fuel_card','telematics','service','inspection')),
  is_correction  BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (vehicle_id, read_at, source),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id)
);

CREATE TABLE fleet.fuel_cards (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  issuer_id      BIGINT NOT NULL,
  number         TEXT NOT NULL,
  status         TEXT NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active','blocked','expired','lost')),
  valid_to       DATE,
  monthly_limit  NUMERIC(14,2),
  UNIQUE (company_id, issuer_id, number),
  FOREIGN KEY (company_id, issuer_id) REFERENCES core.partners (company_id, id),
  UNIQUE (company_id, id)
);

CREATE TABLE fleet.fuel_card_assignments (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  card_id        BIGINT NOT NULL,
  vehicle_id     BIGINT,
  employee_id    BIGINT,
  valid_from     DATE NOT NULL,
  valid_to       DATE,
  EXCLUDE USING gist (card_id WITH =, daterange(valid_from, valid_to) WITH &&),
  FOREIGN KEY (company_id, card_id) REFERENCES fleet.fuel_cards (company_id, id),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, employee_id) REFERENCES core.employees (company_id, id)
);
```

Ograniczenie `EXCLUDE` przy przypisaniach kart pilnuje, żeby jedna karta nie była w tym samym dniu przypisana do dwóch pojazdów. Bez tego import transakcji nie ma jak rozstrzygnąć, czyj był koszt.

```sql
CREATE TABLE fleet.tires (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  set_code       TEXT,
  size           TEXT NOT NULL,
  season         TEXT CHECK (season IN ('summer','winter','all_season')),
  dot            TEXT,
  tread_mm       NUMERIC(4,1),
  status         TEXT NOT NULL DEFAULT 'in_use'
                   CHECK (status IN ('in_use','storage','scrapped')),
  vehicle_id     BIGINT,
  position       TEXT,
  storage_place  TEXT,
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id)
);

CREATE TABLE fleet.fines (                -- mandaty i wykroczenia
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT,
  driver_id      BIGINT,
  occurred_at    TIMESTAMPTZ NOT NULL,
  authority      TEXT,
  reference_no   TEXT,
  amount_gross   NUMERIC(14,2),
  points         SMALLINT,
  driver_named_at DATE,                   -- data wskazania kierowcy
  deadline       DATE,
  status         TEXT NOT NULL DEFAULT 'new'
                   CHECK (status IN ('new','driver_named','paid','appealed','closed')),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, driver_id) REFERENCES core.employees (company_id, id)
);

CREATE TABLE fleet.authorizations (       -- zgody na naprawy
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT NOT NULL,
  partner_id     BIGINT,
  requested_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  limit_net      NUMERIC(14,2),
  status         TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','approved','rejected','settled')),
  approved_by    BIGINT REFERENCES core.users(id),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, partner_id) REFERENCES core.partners (company_id, id),
  UNIQUE (company_id, id)
);

CREATE TABLE fleet.authorization_items (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        BIGINT NOT NULL REFERENCES core.companies(id),
  authorization_id  BIGINT NOT NULL,
  name              TEXT NOT NULL,
  qty               NUMERIC(10,3) NOT NULL DEFAULT 1,
  unit_price_net    NUMERIC(14,2),
  FOREIGN KEY (company_id, authorization_id) REFERENCES fleet.authorizations (company_id, id) ON DELETE CASCADE
);

CREATE TABLE fleet.reminders (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT,
  employee_id    BIGINT,
  kind           TEXT NOT NULL,           -- 'inspection','policy','contract','license','medical'
  due_date       DATE,
  due_mileage_km INT,
  lead_days      INT NOT NULL DEFAULT 30,
  done_at        TIMESTAMPTZ,
  CHECK (due_date IS NOT NULL OR due_mileage_km IS NOT NULL),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, employee_id) REFERENCES core.employees (company_id, id)
);
```

> **Kasowanie pozycji podrzędnych.** `authorization_items` ma własne `company_id` mimo powiązania przez `authorization_id`. To nie jest nadmiarowość — bez tego zapytanie kasujące pozycje po identyfikatorze nadrzędnym omija filtr najemcy. Dokładnie ta luka znalazła się w audycie systemu odniesienia: usuwanie pozycji faktury po identyfikatorze ze ścieżki, z własną spółką w parametrze, czyli poza zasięgiem centralnego strażnika.

### Historia przypisań, protokoły, konflikty źródeł

```sql
-- Komu i gdzie pojazd był przypisany w danym okresie.
-- Źródło prawdy dla rozbicia TCO na MPK i oddział: przeniesienie pojazdu nie zmienia historii.
CREATE TABLE fleet.vehicle_assignments (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT NOT NULL,
  branch_id      BIGINT,
  cost_center_id BIGINT,
  employee_id    BIGINT,                  -- użytkownik pojazdu
  valid_from     DATE NOT NULL,
  valid_to       DATE,
  document_id    BIGINT,   -- np. protokół wydania
  FOREIGN KEY (company_id, vehicle_id)     REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, branch_id)      REFERENCES core.branches (company_id, id),
  FOREIGN KEY (company_id, cost_center_id) REFERENCES core.cost_centers (company_id, id),
  FOREIGN KEY (company_id, employee_id)    REFERENCES core.employees (company_id, id),
  EXCLUDE USING gist (vehicle_id WITH =, daterange(valid_from, valid_to) WITH &&),
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id)
);

-- Protokoły wydania/zdania i oględziny — osobne czynności, jeden format zapisu.
CREATE TABLE fleet.protocols (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT NOT NULL,
  employee_id    BIGINT,
  kind           TEXT NOT NULL CHECK (kind IN ('handover','return','inspection')),
  performed_at   TIMESTAMPTZ NOT NULL,
  mileage_km     INT CHECK (mileage_km >= 0),
  fuel_level_pct SMALLINT CHECK (fuel_level_pct BETWEEN 0 AND 100),
  checklist      JSONB NOT NULL DEFAULT '{}',     -- wyposażenie, stan, uwagi
  signed_by_employee_at TIMESTAMPTZ,
  signed_by_issuer_id   BIGINT REFERENCES core.users(id),
  document_id    BIGINT,  -- PDF protokołu po podpisie
  client_uuid    UUID UNIQUE,                     -- idempotencja zapisu z aplikacji mobilnej (offline)
  FOREIGN KEY (company_id, vehicle_id)  REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, employee_id) REFERENCES core.employees (company_id, id),
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id),
  UNIQUE (company_id, id)
);

CREATE TABLE fleet.protocol_photos (      -- zdjęcia: wejście do rejestru szkód, bez przepisywania
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  protocol_id    BIGINT NOT NULL,
  document_id    BIGINT NOT NULL,
  damage_id      BIGINT,   -- gdy zdjęcie dokumentuje szkodę
  caption        TEXT,
  FOREIGN KEY (company_id, protocol_id) REFERENCES fleet.protocols (company_id, id) ON DELETE CASCADE,
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id),
  FOREIGN KEY (company_id, damage_id) REFERENCES fleet.damages (company_id, id)
);

-- Lista „do rozstrzygnięcia przez człowieka": konflikt źródeł tej samej rangi
-- albo rekord wewnętrznie sprzeczny (M1 przy DMC > 3,5 t, model = status itd.).
CREATE TABLE fleet.data_conflicts (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT NOT NULL,
  field_name     TEXT NOT NULL,
  kind           TEXT NOT NULL CHECK (kind IN
                   ('same_rank_conflict','internal_contradiction','bulk_filled','invalid_type')),
  details        JSONB NOT NULL,                  -- warianty z provenance, reguła, która zadziałała
  detected_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at    TIMESTAMPTZ,
  resolved_by    BIGINT REFERENCES core.users(id),
  resolution     TEXT,
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id)
);
CREATE UNIQUE INDEX uq_conflicts_open
  ON fleet.data_conflicts (vehicle_id, field_name, kind) WHERE resolved_at IS NULL;
```

---

## Schemat `tax`

```sql
CREATE TABLE tax.municipalities (         -- gminy
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  teryt          TEXT NOT NULL UNIQUE,
  name           TEXT NOT NULL,
  voivodeship    TEXT NOT NULL
);

CREATE TABLE tax.rate_sets (              -- uchwała rady gminy na dany rok
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  municipality_id    BIGINT NOT NULL REFERENCES tax.municipalities(id),
  year               INT NOT NULL,
  resolution_no      TEXT NOT NULL,
  source_url         TEXT,
  verified_at        DATE,
  verified_positions INT,                 -- ile pozycji sprawdzono ze źródłem
  UNIQUE (municipality_id, year)
);

CREATE TABLE tax.rates (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  rate_set_id    BIGINT NOT NULL REFERENCES tax.rate_sets(id) ON DELETE CASCADE,
  category_code  TEXT NOT NULL,           -- D1..D14, wg układu deklaracji
  vehicle_kind   TEXT NOT NULL CHECK (vehicle_kind IN
                   ('truck','tractor','trailer','bus')),
  mass_basis     TEXT CHECK (mass_basis IN ('vehicle','combination')),
                                          -- ciężarowy: DMC pojazdu; ciągnik i przyczepa: DMC zespołu
  dmc_min_kg     NUMERIC(10,2),           -- przedział [min, max)
  dmc_max_kg     NUMERIC(10,2),
  axles_min      SMALLINT,                -- NULL = nie dotyczy (poniżej 12 t, autobusy)
  axles_max      SMALLINT,
  suspension     TEXT CHECK (suspension IN ('pneumatic','other')),
                                          -- NULL = nie dotyczy; od 12 t wymagane
  seats_min      SMALLINT,                -- tylko autobusy
  seats_max      SMALLINT,
  fuel_group     TEXT,                    -- NULL = stawka podstawowa; inaczej napędy alternatywne
  amount_pln     NUMERIC(10,2) NOT NULL,
  UNIQUE NULLS NOT DISTINCT
    (rate_set_id, vehicle_kind, dmc_min_kg, axles_min, suspension, seats_min, fuel_group),
  CHECK (dmc_min_kg IS NULL OR dmc_min_kg < 12000 OR vehicle_kind = 'bus' OR suspension IS NOT NULL)
);
```

**Klucz stawki ma pięć wymiarów, nie trzy.** Od 12 t stawka zależy od liczby osi **i** od tego, czy zawieszenie osi jezdnych jest pneumatyczne (lub uznane za równoważne), czy inne. Ciągnik siodłowy i przyczepa liczone są od **DMC zespołu**, nie własnej. Autobus — od liczby miejsc. Ostatnie `CHECK` nie pozwala zapisać stawki powyżej 12 t bez wskazania zawieszenia — to ta sama klasa błędu co brak liczby osi, tylko w tabeli stawek zamiast w kartotece.

Silnik, który znajdzie dla pojazdu **zero albo więcej niż jedną** pasującą pozycję, nie wybiera „pierwszej" — zwraca brak wyliczenia z listą pól blokujących.

`fuel_group` istnieje, choć dziś żaden pojazd tej floty się nie kwalifikuje. Uchwała warszawska ma paragraf ze stawkami dla napędów wodorowych, hybrydowych, elektrycznych, CNG i LNG — **niższymi o około 40%**. Kolumna i wartości są w bazie, żeby pierwszy taki pojazd dostał poprawną stawkę, a nie zawyżoną.

```sql
CREATE TABLE tax.declarations (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        BIGINT NOT NULL REFERENCES core.companies(id),
  municipality_id   BIGINT NOT NULL REFERENCES tax.municipalities(id),
  year              INT NOT NULL,
  form              TEXT NOT NULL DEFAULT 'DT-1' CHECK (form IN ('DT-1','DT-1/A')),
  status            TEXT NOT NULL DEFAULT 'draft'
                      CHECK (status IN ('draft','ready','filed','corrected')),
  correction_of     BIGINT,
  total_amount_pln  NUMERIC(14,2),
  filed_at          TIMESTAMPTZ,
  document_id       BIGINT,
  FOREIGN KEY (company_id, correction_of) REFERENCES tax.declarations (company_id, id),
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id),
  UNIQUE (company_id, id)
);

CREATE TABLE tax.declaration_lines (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        BIGINT NOT NULL REFERENCES core.companies(id),
  declaration_id    BIGINT NOT NULL,
  vehicle_id        BIGINT NOT NULL,
  category_code     TEXT NOT NULL,
  rate_id           BIGINT REFERENCES tax.rates(id),
  months_owned      SMALLINT NOT NULL CHECK (months_owned BETWEEN 1 AND 12),
  amount_pln        NUMERIC(14,2) NOT NULL,
  exemption         TEXT,                 -- np. 'special_vehicle'
  blocking_fields   TEXT[],               -- pola, których brak uniemożliwia wyliczenie
  UNIQUE (declaration_id, vehicle_id),
  FOREIGN KEY (company_id, declaration_id) REFERENCES tax.declarations (company_id, id) ON DELETE CASCADE,
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id)
);
```

`blocking_fields` jest kolumną wynikową, ale trzymaną, a nie liczoną w locie. Zawiera **tylko te pola, które silnik przy danym tonażu faktycznie przeczyta** — poniżej 12 t liczba osi nie blokuje niczego. Rozróżnienie między „pole jest puste" a „pole blokuje wyliczenie" jest tu materialne: pierwsza liczba to porządek, druga to pieniądze.

```sql
CREATE TABLE tax.env_fee_rates (          -- opłata środowiskowa
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  year           INT NOT NULL,
  fuel_group     TEXT NOT NULL,           -- w tym CNG fabryczny i CNG przebudowany OSOBNO
  euro_standard  TEXT NOT NULL,
  vehicle_class  TEXT NOT NULL,           -- 'passenger','lcv_to_3_5t','above_3_5t'
  rate_per_mg    NUMERIC(10,4) NOT NULL,
  source_ref     TEXT NOT NULL,
  UNIQUE (year, fuel_group, euro_standard, vehicle_class)
);
```

> **Klucz trójwymiarowy jest tu istotą sprawy.** Wcześniejsza struktura miała klucz `paliwo|EURO` — dwa wymiary. Tabela źródłowa ma trzy; brakowało **klasy pojazdu**, a to różnica rzędu 60%. Olej napędowy EURO 5, stawki na 2026: osobowy 5,76 zł/Mg, do 3,5 t inny niż osobowy 6,82, powyżej 3,5 t 9,19. Flota to głównie dwie ostatnie klasy — stawka osobowa zaniżyłaby należność o około 40%, a wynik wyglądałby wiarygodnie.
>
> Drugi, niezależny brak: obwieszczenie **nie podaje gęstości paliw**, więc przeliczenie litrów na megagramy wymaga osobnego źródła. Do czasu uzupełnienia obu rzeczy wyliczenie opłaty ma **odmawiać**, a nie szacować.

---

## Schemat `fin`

```sql
CREATE TABLE fin.invoices (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        BIGINT NOT NULL REFERENCES core.companies(id),
  direction         TEXT NOT NULL CHECK (direction IN ('purchase','sale')),
  partner_id        BIGINT NOT NULL,
  number            TEXT NOT NULL,
  issue_date        DATE NOT NULL,
  sale_date         DATE,
  due_date          DATE,
  net_total         NUMERIC(14,2) NOT NULL,
  vat_total         NUMERIC(14,2) NOT NULL,
  gross_total       NUMERIC(14,2) NOT NULL,
  currency          CHAR(3) NOT NULL DEFAULT 'PLN',
  exchange_rate     NUMERIC(12,6),
  ksef_ref          TEXT,
  ksef_status       TEXT CHECK (ksef_status IN
                      ('not_applicable','pending','queued','sent','accepted','rejected')),
  document_id       BIGINT,
  UNIQUE (company_id, direction, partner_id, number),
  FOREIGN KEY (company_id, partner_id) REFERENCES core.partners (company_id, id),
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id),
  UNIQUE (company_id, id)
);

CREATE TABLE fin.invoice_items (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        BIGINT NOT NULL REFERENCES core.companies(id),
  invoice_id        BIGINT NOT NULL,
  vehicle_id        BIGINT,
  event_id          BIGINT,                    -- powiązanie ze zdarzeniem floty...
  event_occurred_at TIMESTAMPTZ,               -- ...wraz z kluczem partycji
  name              TEXT NOT NULL,
  qty               NUMERIC(12,3) NOT NULL DEFAULT 1,
  unit_net          NUMERIC(14,4) NOT NULL,
  vat_rate          NUMERIC(5,2) NOT NULL,
  net_amount        NUMERIC(14,2) NOT NULL,
  vat_deduction_pct SMALLINT CHECK (vat_deduction_pct IN (0, 50, 100)),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, event_id, event_occurred_at)
    REFERENCES fleet.events (company_id, id, occurred_at),
  CHECK ((event_id IS NULL) = (event_occurred_at IS NULL)),
  FOREIGN KEY (company_id, invoice_id) REFERENCES fin.invoices (company_id, id) ON DELETE CASCADE,
  UNIQUE (company_id, id)
);

CREATE TABLE fin.postings (               -- dekrety
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        BIGINT NOT NULL REFERENCES core.companies(id),
  invoice_item_id   BIGINT,
  event_id          BIGINT,
  event_occurred_at TIMESTAMPTZ,
  account           TEXT NOT NULL,
  cost_center_id    BIGINT,
  branch_id         BIGINT,
  amount            NUMERIC(14,2) NOT NULL,
  period            DATE NOT NULL,             -- pierwszy dzień miesiąca księgowania
  exported_at       TIMESTAMPTZ,
  FOREIGN KEY (company_id, event_id, event_occurred_at)
    REFERENCES fleet.events (company_id, id, occurred_at),
  FOREIGN KEY (company_id, cost_center_id) REFERENCES core.cost_centers (company_id, id),
  FOREIGN KEY (company_id, branch_id)      REFERENCES core.branches (company_id, id),
  FOREIGN KEY (company_id, invoice_item_id) REFERENCES fin.invoice_items (company_id, id) ON DELETE SET NULL (invoice_item_id)
);
CREATE INDEX ix_postings_period ON fin.postings (company_id, period);
```

**Pozycja faktury wskazuje zdarzenie prawdziwym kluczem obcym.** `fleet.events` jest partycjonowana, więc jej klucz główny to `(id, occurred_at)` i taki też musi być klucz obcy — PostgreSQL 12+ obsługuje klucze obce do tabel partycjonowanych. Bez tego `event_id` jest zwykłą liczbą, która po skasowaniu albo przeniesieniu zdarzenia wskazuje w próżnię, a zasada „zdarzenie zapisane raz" trzyma się wyłącznie na dyscyplinie kodu.

```sql

CREATE TABLE fin.fixed_assets (           -- środki trwałe
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id        BIGINT,
  inventory_no      TEXT NOT NULL,
  kst               TEXT,
  initial_value     NUMERIC(14,2) NOT NULL,
  method            TEXT NOT NULL CHECK (method IN ('linear','degressive','one_time')),
  rate_pct          NUMERIC(5,2) NOT NULL,
  started_on        DATE NOT NULL,
  ended_on          DATE,
  UNIQUE (company_id, inventory_no),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  UNIQUE (company_id, id)
);

CREATE TABLE fin.depreciation (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        BIGINT NOT NULL REFERENCES core.companies(id),
  asset_id          BIGINT NOT NULL,
  period            DATE NOT NULL,
  amount            NUMERIC(14,2) NOT NULL,
  UNIQUE (asset_id, period),
  FOREIGN KEY (company_id, asset_id) REFERENCES fin.fixed_assets (company_id, id) ON DELETE CASCADE
);
```

---

## Schemat `rent`

```sql
CREATE TABLE rent.price_lists (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  name           TEXT NOT NULL,
  valid_from     DATE NOT NULL,
  valid_to       DATE,
  partner_id     BIGINT,   -- NULL = cennik ogólny
  FOREIGN KEY (company_id, partner_id) REFERENCES core.partners (company_id, id),
  UNIQUE (company_id, id)
);

CREATE TABLE rent.price_list_items (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  price_list_id  BIGINT NOT NULL,
  vehicle_group  TEXT NOT NULL,
  period_unit    TEXT NOT NULL CHECK (period_unit IN ('hour','day','month')),
  min_periods    INT NOT NULL DEFAULT 1,
  price_net      NUMERIC(14,2) NOT NULL,
  mileage_incl   INT,
  extra_km_net   NUMERIC(10,2),
  FOREIGN KEY (company_id, price_list_id) REFERENCES rent.price_lists (company_id, id) ON DELETE CASCADE
);

CREATE TABLE rent.reservations (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT,
  vehicle_group  TEXT,
  partner_id     BIGINT,
  starts_at      TIMESTAMPTZ NOT NULL,
  ends_at        TIMESTAMPTZ NOT NULL,
  status         TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','accepted','rejected','cancelled','completed')),
  CHECK (ends_at > starts_at),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, partner_id) REFERENCES core.partners (company_id, id),
  UNIQUE (company_id, id)
);
```

> **Słownik statusu rezerwacji jest jeden.** Poprzedni system miał dwie tabele rezerwacji z różnymi zestawami statusów; interfejs oferował wartość, której ograniczenie w bazie nie dopuszczało, więc zapis kończył się błędem. Drugi, niezgłoszony objaw: istniejące wiersze renderowały się jako surowa wartość techniczna, bo mapa etykiet nie miała takiego klucza. Lista w `CHECK` i lista etykiet w interfejsie pochodzą z jednego miejsca.

```sql
CREATE TABLE rent.orders (                -- zlecenia najmu
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  reservation_id BIGINT,
  vehicle_id     BIGINT NOT NULL,
  partner_id     BIGINT NOT NULL,
  driver_name    TEXT,
  issued_at      TIMESTAMPTZ NOT NULL,
  returned_at    TIMESTAMPTZ,
  mileage_out    INT,
  mileage_in     INT,
  deposit_amount NUMERIC(14,2),
  deposit_status TEXT CHECK (deposit_status IN ('held','released','charged')),
  status         TEXT NOT NULL DEFAULT 'open'
                   CHECK (status IN ('open','closed','settled','cancelled')),
  FOREIGN KEY (company_id, reservation_id) REFERENCES rent.reservations (company_id, id),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, partner_id) REFERENCES core.partners (company_id, id)
);
```

---

## Schemat `tms`

> **Zakres zawężony 22.09.2026.** Spedycja morska i lotnicza, obsługa celna (agencja, skład celny, gwarancje) i zgłoszenia fitosanitarne **wypadły z projektu** — uzasadnienie w [roadmapie](07-roadmap.md). Tabele poniżej obsługują transport drogowy i kontenerowy. Wartości `'forwarding'` i `'intermodal'` w `kind` zostają w słowniku, żeby rozszerzenie nie wymagało migracji, ale odpowiadających im tabel nie budujemy.

```sql
CREATE TABLE tms.orders (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  number         TEXT NOT NULL,
  kind           TEXT NOT NULL CHECK (kind IN ('transport','forwarding','intermodal')),
  customer_id    BIGINT NOT NULL,
  carrier_id     BIGINT,
  vehicle_id     BIGINT,
  trailer_id     BIGINT,
  driver_id      BIGINT,
  loading_at     TIMESTAMPTZ,
  unloading_at   TIMESTAMPTZ,
  freight_net    NUMERIC(14,2),
  currency       CHAR(3) NOT NULL DEFAULT 'PLN',
  status         TEXT NOT NULL DEFAULT 'new'
                   CHECK (status IN ('new','planned','in_progress','delivered','settled','cancelled')),
  UNIQUE (company_id, number),
  FOREIGN KEY (company_id, customer_id) REFERENCES core.partners (company_id, id),
  FOREIGN KEY (company_id, carrier_id) REFERENCES core.partners (company_id, id),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, trailer_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, driver_id) REFERENCES core.employees (company_id, id),
  UNIQUE (company_id, id)
);

CREATE TABLE tms.order_stops (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  order_id       BIGINT NOT NULL,
  seq            INT NOT NULL,
  kind           TEXT NOT NULL CHECK (kind IN ('loading','unloading','customs','terminal')),
  address_id     BIGINT,
  planned_at     TIMESTAMPTZ,
  actual_at      TIMESTAMPTZ,
  UNIQUE (order_id, seq),
  FOREIGN KEY (company_id, order_id) REFERENCES tms.orders (company_id, id) ON DELETE CASCADE,
  FOREIGN KEY (company_id, address_id) REFERENCES core.addresses (company_id, id)
);

CREATE TABLE tms.transport_docs (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  order_id       BIGINT NOT NULL,
  kind           TEXT NOT NULL,           -- 'CMR','packing_list','customs','booking'
  number         TEXT,
  document_id    BIGINT,
  FOREIGN KEY (company_id, order_id) REFERENCES tms.orders (company_id, id) ON DELETE CASCADE,
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id)
);
```

---

## Schematy pozostałe

```sql
-- docs
CREATE TABLE docs.documents (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  kind           TEXT NOT NULL,           -- 'invoice','policy','registration','protocol','cmr'
  storage_key    TEXT NOT NULL,           -- klucz w magazynie obiektowym
  mime_type      TEXT NOT NULL,
  size_bytes     BIGINT NOT NULL,
  sha256         TEXT NOT NULL,
  uploaded_by    BIGINT REFERENCES core.users(id),
  uploaded_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, sha256),             -- ten sam plik nie wchodzi dwa razy
  UNIQUE (company_id, id)
);

CREATE TABLE docs.ocr_results (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  document_id    BIGINT NOT NULL,
  layer          TEXT NOT NULL CHECK (layer IN ('aztec','ocr_service','vision_model')),
  fields         JSONB NOT NULL,
  raw_output     JSONB,
  fallback_reason TEXT,                   -- dlaczego zeszliśmy z wyższej warstwy
  confirmed_by   BIGINT REFERENCES core.users(id),
  confirmed_at   TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id) ON DELETE CASCADE
);

-- telematics
CREATE TABLE telematics.positions (
  id             BIGINT GENERATED ALWAYS AS IDENTITY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT NOT NULL,
  recorded_at    TIMESTAMPTZ NOT NULL,
  lat            NUMERIC(9,6),
  lon            NUMERIC(9,6),
  speed_kmh      NUMERIC(6,2),
  ignition       BOOLEAN,
  engine_rpm     INT,                     -- praca z PTO: obroty, nie zapłon
  PRIMARY KEY (id, recorded_at),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id)
) PARTITION BY RANGE (recorded_at);
-- Punkty z okresu jazdy prywatnej NIE trafiają do positions: importer odrzuca je
-- po oknie z private_trips i zapisuje wyłącznie fakt i dystans.

CREATE TABLE telematics.private_trips (    -- jazdy prywatne: fakt i dystans, bez trasy
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT NOT NULL,
  employee_id    BIGINT,
  started_at     TIMESTAMPTZ NOT NULL,
  ended_at       TIMESTAMPTZ NOT NULL,
  distance_km    NUMERIC(9,1) NOT NULL CHECK (distance_km >= 0),
  source         TEXT NOT NULL CHECK (source IN ('telematics','driver_declared')),
  FOREIGN KEY (company_id, vehicle_id)  REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, employee_id) REFERENCES core.employees (company_id, id),
  CHECK (ended_at > started_at)
);

-- assets — wyposażenie pracownika, telefony, oświadczenia
CREATE TABLE assets.items (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  kind           TEXT NOT NULL CHECK (kind IN ('phone','sim','laptop','card','clothing','tool','other')),
  name           TEXT NOT NULL,
  serial_no      TEXT,
  phone_number   TEXT,                    -- dla 'phone'/'sim'; rozliczenie billingów
  monthly_limit  NUMERIC(14,2),
  status         TEXT NOT NULL DEFAULT 'in_stock'
                   CHECK (status IN ('in_stock','issued','repair','lost','scrapped')),
  UNIQUE (company_id, id)
);

CREATE TABLE assets.issues (               -- wydanie i zdanie sprzętu
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  item_id        BIGINT NOT NULL,
  employee_id    BIGINT NOT NULL,
  issued_on      DATE NOT NULL,
  returned_on    DATE,
  issue_document_id  BIGINT,
  return_document_id BIGINT,
  FOREIGN KEY (company_id, item_id)     REFERENCES assets.items (company_id, id),
  FOREIGN KEY (company_id, employee_id) REFERENCES core.employees (company_id, id),
  EXCLUDE USING gist (item_id WITH =, daterange(issued_on, returned_on) WITH &&),
  FOREIGN KEY (company_id, issue_document_id) REFERENCES docs.documents (company_id, id),
  FOREIGN KEY (company_id, return_document_id) REFERENCES docs.documents (company_id, id)
);

CREATE TABLE assets.statements (           -- oświadczenia: użytkowanie służbowe, zgody, regulamin
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  employee_id    BIGINT NOT NULL,
  vehicle_id     BIGINT,
  kind           TEXT NOT NULL CHECK (kind IN
                   ('business_use_only','mixed_use','gps_policy_ack','regulations_ack','consent')),
  valid_from     DATE NOT NULL,
  valid_to       DATE,
  signed_at      TIMESTAMPTZ NOT NULL,
  document_id    BIGINT,
  FOREIGN KEY (company_id, employee_id) REFERENCES core.employees (company_id, id),
  FOREIGN KEY (company_id, vehicle_id)  REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id)
);

-- integr
CREATE TABLE integr.raw_responses (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT REFERENCES core.companies(id),
  provider       TEXT NOT NULL,
  endpoint       TEXT NOT NULL,
  request        JSONB,
  response       JSONB,
  http_status    INT,
  error_code     TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE integr.outbox (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  topic          TEXT NOT NULL,
  payload        JSONB NOT NULL,
  attempts       SMALLINT NOT NULL DEFAULT 0,
  last_error     TEXT,
  available_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at   TIMESTAMPTZ
);

-- audit
CREATE TABLE audit.audit_logs (
  id             BIGINT GENERATED ALWAYS AS IDENTITY,
  company_id     BIGINT REFERENCES core.companies(id),
  user_id        BIGINT REFERENCES core.users(id),
  occurred_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  action         TEXT NOT NULL,           -- 'create','update','delete','export','login','access_denied'
  entity         TEXT NOT NULL,
  entity_id      BIGINT,
  before         JSONB,
  after          JSONB,
  ip             INET,
  row_count      INT,                     -- dla eksportów
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);
```

## Polityki RLS

### Kontekst żądania

Aplikacja ustawia na początku każdej transakcji dwie zmienne, **obie wyliczone z `core.user_company_access`**, nigdy z parametru żądania:

```sql
SET LOCAL app.company_ids = '3,7,12';   -- wszystkie spółki z jawnych nadań użytkownika (odczyt)
SET LOCAL app.company_id  = '3';        -- aktywna spółka (zapis)
SET LOCAL app.user_id     = '41';       -- użytkownik; dla polityk zależnych od flag nadania
```

Zwykły użytkownik ma jedną spółkę w obu zmiennych. Operator wielospółkowy czyta zestawienia przekrojowe ze wszystkich swoich spółek, ale **zapisuje zawsze w jednej, aktywnej**.

### Granica zaufania

Zmienne `app.*` może ustawić każdy, kto wykonuje SQL jako `fleetcore_app`. RLS chroni więc przed **błędem w kodzie aplikacji** (zapomniany filtr, IDOR na pojedynczym rekordzie), a nie przed kimś, kto wykonuje dowolny SQL na połączeniu aplikacji. Dlatego obowiązuje:

- **wyłącznie zapytania parametryzowane** przez warstwę dostępu do danych; zakaz składania SQL z łańcuchów — bramka w CI szuka interpolacji w wywołaniach zapytań;
- zmienne ustawia **jedna funkcja w warstwie połączenia** na podstawie sesji z bazy, w tej samej transakcji co zapytanie (`SET LOCAL`), nigdy kod modułu;
- rola `fleetcore_app` nie ma prawa tworzyć funkcji, schematów ani wykonywać `COPY ... PROGRAM`;
- dostęp do bazy z zewnątrz tylko przez sieć prywatną; poświadczenia `fleetcore_app` nie trafiają do ludzi.

Wzmocnienie na później, gdy pojawi się klient wymagający tego w audycie: polityki porównują `company_id` z wynikiem funkcji `SECURITY DEFINER`, która wylicza spółki z tabeli sesji po skrócie losowego tokenu sesji. Podrobienie kontekstu wymagałoby wtedy cudzego tokenu, a nie tylko instrukcji `SET`.

### Wzorzec polityki — dla każdej tabeli z `company_id`

```sql
ALTER TABLE fleet.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE fleet.vehicles FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_read ON fleet.vehicles FOR SELECT
  USING (company_id = ANY (string_to_array(current_setting('app.company_ids'), ',')::BIGINT[]));

CREATE POLICY tenant_write ON fleet.vehicles FOR ALL
  USING      (company_id = current_setting('app.company_id')::BIGINT)
  WITH CHECK (company_id = current_setting('app.company_id')::BIGINT);
```

- `FORCE` jest konieczne — bez niego polityka nie dotyczy właściciela tabeli.
- Rola `fleetcore_app` nie ma `BYPASSRLS`.
- `current_setting` **bez** drugiego argumentu: nieustawiona zmienna daje błąd, nie pusty wynik ani pełny dostęp. Zamknięcie na brak kontekstu jest zamierzone.
- `WITH CHECK` blokuje zapis rekordu do cudzej spółki, nie tylko odczyt.

Polityki nakłada **migracja generująca je dla każdej tabeli z kolumną `company_id`**, a bramka `tenant-isolation` sprawdza w katalogu systemowym, że żadna taka tabela nie ma `relrowsecurity = false`. Tabela bez polityki to porażka CI, nie przeoczenie do przeglądu.

Wyjątki z jawną regułą:

| Tabela | Reguła |
| --- | --- |
| `core.dictionaries` | odczyt: `company_id IS NULL OR company_id = ANY(...)` — słowniki systemowe widzi każdy; zapis tylko własnych |
| `audit.audit_logs` | `fleetcore_app` ma `INSERT` oraz `SELECT` objęty polityką `tenant_read` (tylko nadane spółki); w API odczyt dostępny wyłącznie dla roli `admin` w danej spółce. Bez `UPDATE` i `DELETE` dla kogokolwiek poza retencją na `fleetcore_maint` |
| `telematics.positions` | odczyt tylko gdy nadanie użytkownika w tej spółce ma `can_view_routes = true` — dodatkowa polityka `route_read` sprawdza wiersz w `core.user_company_access` dla `app.user_id`; każdy odczyt tras przez API zapisuje wpis `action = 'route_access'` w audycie. Agregaty przebiegów (bez punktów) dostępne bez flagi |
| `integr.raw_responses` | jak tabele najemcy; wiersze bez `company_id` (np. odpowiedzi słownikowe) czyta tylko `fleetcore_maint` |
| `tax.municipalities`, `tax.rate_sets`, `tax.rates`, `tax.env_fee_rates` | dane referencyjne bez `company_id` — odczyt dla wszystkich, zapis tylko z migracji |

## Widoki materializowane

```sql
-- Właścicielem jest fleetcore_maint (BYPASSRLS): odświeżanie widzi zdarzenia WSZYSTKICH spółek.
-- Pod właścicielem z FORCE RLS odświeżenie albo padłoby na braku app.company_id,
-- albo policzyłoby jedną spółkę i cicho nadpisało resztę.
CREATE MATERIALIZED VIEW fleet.mv_vehicle_tco AS
SELECT company_id, vehicle_id,
       date_trunc('month', occurred_at)::DATE AS period,
       SUM(amount_net) FILTER (WHERE kind = 'refuel')               AS fuel_net,
       SUM(amount_net) FILTER (WHERE kind IN ('service','repair'))  AS service_net,
       SUM(amount_net) FILTER (WHERE kind = 'insurance')            AS insurance_net,
       SUM(amount_net) FILTER (WHERE kind = 'lease_payment')        AS lease_net,
       SUM(amount_net) FILTER (WHERE kind = 'toll')                 AS toll_net,
       SUM(amount_net)                                              AS total_net
FROM fleet.events
WHERE amount_net IS NOT NULL
GROUP BY 1, 2, 3;

CREATE UNIQUE INDEX ON fleet.mv_vehicle_tco (company_id, vehicle_id, period);
ALTER MATERIALIZED VIEW fleet.mv_vehicle_tco OWNER TO fleetcore_maint;

-- Aplikacja NIE ma dostępu do widoku materializowanego...
REVOKE ALL ON fleet.mv_vehicle_tco FROM PUBLIC, fleetcore_app;

-- ...tylko do widoku filtrującego po spółkach z kontekstu żądania.
CREATE VIEW fleet.v_vehicle_tco WITH (security_barrier) AS
SELECT * FROM fleet.mv_vehicle_tco
WHERE company_id = ANY (string_to_array(current_setting('app.company_ids'), ',')::BIGINT[]);
GRANT SELECT ON fleet.v_vehicle_tco TO fleetcore_app;
```

> **Widok materializowany nie podlega RLS.** Przechowuje gotowe wiersze; zapytanie do niego nie uruchamia polityk tabeli `fleet.events`. Kto ma `SELECT` na widoku materializowanym, widzi wszystkie spółki. Dlatego aplikacja dostaje wyłącznie widok `v_vehicle_tco` z filtrem w samej definicji, a bramka `tenant-isolation` sprawdza, że rola aplikacji nie ma uprawnień do żadnego widoku materializowanego.

Odświeżanie `CONCURRENTLY` w nocy, zadaniem `mv-refresh` na roli `fleetcore_maint`. Rola musi mieć `SELECT` na każdej tabeli źródłowej widoku (tu: `fleet.events`) — bez tego odświeżenie kończy się `permission denied`, a raporty pokazują wczorajszy stan. Alert, gdy ostatnie odświeżenie starsze niż 26 h ([wdrożenie](08-cluster-deployment.md)).

**Zakres widoku vs definicja TCO.** Widok liczy składniki zapisane jako zdarzenia z kwotą. Pełne TCO z [modelu danych](05-data-model-and-analytics.md) składa raport z czterech źródeł: ten widok + `fin.depreciation` (amortyzacja) + `tax.declaration_lines` (podatek, rozłożony na miesiące posiadania) + VAT odzyskany z `fin.invoice_items` + przychody z `rent.orders`. Rozbicie na MPK i oddział przez `fleet.vehicle_assignments` z okresu, nie bieżące przypisanie z kartoteki.

## Zestawienie kluczy obcych o nieoczywistym zachowaniu

| Relacja | Reguła | Dlaczego |
| --- | --- | --- |
| `vehicle_plates → vehicles` | `ON DELETE CASCADE` | historia numerów nie ma sensu bez pojazdu |
| `events → vehicles` | **brak kaskady** | zdarzenia zostają; pojazd kasujemy miękko |
| `declaration_lines → vehicles` | **brak kaskady** | deklaracja złożona musi zostać odtwarzalna |
| `invoice_items → invoices` | `ON DELETE CASCADE` + własne `company_id` | patrz uwaga o kasowaniu pozycji |
| `postings → invoice_items` | `SET NULL` | dekret wyeksportowany do księgowości żyje dalej |
| `fixed_assets → vehicles` | **brak kaskady** | środek trwały bywa zbywany osobno |
