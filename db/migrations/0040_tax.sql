-- Wygenerowane z docs/10-database-design.md i docs/16-platforma-integracji.md (tools/gen-migrations-from-docs.py).
-- Uzasadnienia kolumn i ograniczeń: w dokumentacji. Po wygenerowaniu plik edytuje się ręcznie — NIE generuje się go ponownie.

CREATE TABLE tax.municipalities (         
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  teryt          TEXT NOT NULL UNIQUE,
  name           TEXT NOT NULL,
  voivodeship    TEXT NOT NULL
);

CREATE TABLE tax.rate_sets (              
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  municipality_id    BIGINT NOT NULL REFERENCES tax.municipalities(id),
  year               INT NOT NULL,
  resolution_no      TEXT NOT NULL,
  source_url         TEXT,
  verified_at        DATE,
  verified_positions INT,                 
  UNIQUE (municipality_id, year)
);

CREATE TABLE tax.rates (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  rate_set_id    BIGINT NOT NULL REFERENCES tax.rate_sets(id) ON DELETE CASCADE,
  category_code  TEXT NOT NULL,           
  vehicle_kind   TEXT NOT NULL CHECK (vehicle_kind IN
                   ('truck','tractor','trailer','bus')),
  mass_basis     TEXT CHECK (mass_basis IN ('vehicle','combination')),
                                          
  dmc_min_kg     NUMERIC(10,2),           
  dmc_max_kg     NUMERIC(10,2),
  axles_min      SMALLINT,                
  axles_max      SMALLINT,
  suspension     TEXT CHECK (suspension IN ('pneumatic','other')),
                                          
  seats_min      SMALLINT,                
  seats_max      SMALLINT,
  fuel_group     TEXT,                    
  amount_pln     NUMERIC(10,2) NOT NULL,
  UNIQUE NULLS NOT DISTINCT
    (rate_set_id, vehicle_kind, dmc_min_kg, axles_min, suspension, seats_min, fuel_group),
  CHECK (dmc_min_kg IS NULL OR dmc_min_kg < 12000 OR vehicle_kind = 'bus' OR suspension IS NOT NULL)
);

CREATE TABLE tax.env_fee_rates (          
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  year           INT NOT NULL,
  fuel_group     TEXT NOT NULL,           
  euro_standard  TEXT NOT NULL,
  vehicle_class  TEXT NOT NULL,           
  rate_per_mg    NUMERIC(10,4) NOT NULL,
  source_ref     TEXT NOT NULL,
  UNIQUE (year, fuel_group, euro_standard, vehicle_class)
);

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
  exemption         TEXT,                 
  blocking_fields   TEXT[],               
  UNIQUE (declaration_id, vehicle_id),
  FOREIGN KEY (company_id, declaration_id) REFERENCES tax.declarations (company_id, id) ON DELETE CASCADE,
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id)
);
