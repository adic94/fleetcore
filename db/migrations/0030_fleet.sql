-- Wygenerowane z docs/10-database-design.md i docs/16-platforma-integracji.md (tools/gen-migrations-from-docs.py).
-- Uzasadnienia kolumn i ograniczeń: w dokumentacji. Po wygenerowaniu plik edytuje się ręcznie — NIE generuje się go ponownie.

CREATE TABLE fleet.vehicles (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id         BIGINT NOT NULL REFERENCES core.companies(id),
  vin                TEXT,                      
  plate              TEXT NOT NULL,             
                                                
  brand              TEXT,
  model              TEXT,
  kind               TEXT,                      
  homolog_category   TEXT,                      
  homolog_no         TEXT,
  production_year    INT CHECK (production_year BETWEEN 1900 AND 2100),
  first_reg_date     DATE,

  
  dmc_kg             NUMERIC(10,2) CHECK (dmc_kg > 0),
  curb_weight_kg     NUMERIC(10,2) CHECK (curb_weight_kg > 0),
  combo_dmc_kg       NUMERIC(10,2) CHECK (combo_dmc_kg > 0),
  axles_count        SMALLINT CHECK (axles_count BETWEEN 1 AND 10),
  suspension_type    TEXT CHECK (suspension_type IN ('pneumatic','other')),
                                                
  engine_cc          INT CHECK (engine_cc > 0),
  power_kw           NUMERIC(7,2) CHECK (power_kw > 0),
  fuel_type          TEXT,
  euro_standard      TEXT,
  seats              SMALLINT CHECK (seats > 0),

  branch_id          BIGINT,                    
  cost_center_id     BIGINT,
  status             TEXT NOT NULL DEFAULT 'active'
                       CHECK (status IN ('active','sold','scrapped','reserve','leased_out')),
  acquired_on        DATE,
  disposed_on        DATE,
  extra              JSONB NOT NULL DEFAULT '{}',   
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

CREATE TABLE fleet.fines (                
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT,
  driver_id      BIGINT,
  occurred_at    TIMESTAMPTZ NOT NULL,
  authority      TEXT,
  reference_no   TEXT,
  amount_gross   NUMERIC(14,2),
  points         SMALLINT,
  driver_named_at DATE,                   
  deadline       DATE,
  status         TEXT NOT NULL DEFAULT 'new'
                   CHECK (status IN ('new','driver_named','paid','appealed','closed')),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, driver_id) REFERENCES core.employees (company_id, id)
);

CREATE TABLE fleet.authorizations (       
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
  kind           TEXT NOT NULL,           
  due_date       DATE,
  due_mileage_km INT,
  lead_days      INT NOT NULL DEFAULT 30,
  done_at        TIMESTAMPTZ,
  CHECK (due_date IS NOT NULL OR due_mileage_km IS NOT NULL),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, employee_id) REFERENCES core.employees (company_id, id)
);

CREATE TABLE fleet.data_conflicts (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT NOT NULL,
  field_name     TEXT NOT NULL,
  kind           TEXT NOT NULL CHECK (kind IN
                   ('same_rank_conflict','internal_contradiction','bulk_filled','invalid_type')),
  details        JSONB NOT NULL,                  
  detected_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at    TIMESTAMPTZ,
  resolved_by    BIGINT REFERENCES core.users(id),
  resolution     TEXT,
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id)
);

CREATE UNIQUE INDEX uq_conflicts_open
  ON fleet.data_conflicts (vehicle_id, field_name, kind) WHERE resolved_at IS NULL;

CREATE TABLE fleet.vehicle_plates (       
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
  source        TEXT NOT NULL,             
  external_ref  TEXT,                      
  payload       JSONB NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by    BIGINT REFERENCES core.users(id),
  PRIMARY KEY (id, occurred_at),
  UNIQUE (company_id, id, occurred_at),     
  FOREIGN KEY (company_id, vehicle_id)  REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, employee_id) REFERENCES core.employees (company_id, id),
  CHECK (vehicle_id IS NOT NULL OR employee_id IS NOT NULL),
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id)
) PARTITION BY RANGE (occurred_at);

CREATE INDEX ix_events_vehicle ON fleet.events (company_id, vehicle_id, occurred_at DESC);

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

CREATE TABLE fleet.contracts (            
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT,
  partner_id     BIGINT NOT NULL,
  kind           TEXT NOT NULL CHECK (kind IN ('lease','rental','credit','service','purchase')),
  number         TEXT NOT NULL,
  start_date     DATE NOT NULL,
  end_date       DATE,
  mileage_limit  INT,                      
  value_net      NUMERIC(14,2),
  currency       CHAR(3) NOT NULL DEFAULT 'PLN',
  document_id    BIGINT,
  UNIQUE (company_id, partner_id, number),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, partner_id) REFERENCES core.partners (company_id, id),
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id),
  UNIQUE (company_id, id)
);

CREATE TABLE fleet.contract_schedule (    
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

CREATE TABLE fleet.policies (             
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT NOT NULL,
  insurer_id     BIGINT NOT NULL,
  number         TEXT NOT NULL,
  scope          TEXT[] NOT NULL,               
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

CREATE TABLE fleet.damages (              
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

CREATE TABLE fleet.vehicle_assignments (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT NOT NULL,
  branch_id      BIGINT,
  cost_center_id BIGINT,
  employee_id    BIGINT,                  
  valid_from     DATE NOT NULL,
  valid_to       DATE,
  document_id    BIGINT,   
  FOREIGN KEY (company_id, vehicle_id)     REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, branch_id)      REFERENCES core.branches (company_id, id),
  FOREIGN KEY (company_id, cost_center_id) REFERENCES core.cost_centers (company_id, id),
  FOREIGN KEY (company_id, employee_id)    REFERENCES core.employees (company_id, id),
  EXCLUDE USING gist (vehicle_id WITH =, daterange(valid_from, valid_to) WITH &&),
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id)
);

CREATE TABLE fleet.protocols (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT NOT NULL,
  employee_id    BIGINT,
  kind           TEXT NOT NULL CHECK (kind IN ('handover','return','inspection')),
  performed_at   TIMESTAMPTZ NOT NULL,
  mileage_km     INT CHECK (mileage_km >= 0),
  fuel_level_pct SMALLINT CHECK (fuel_level_pct BETWEEN 0 AND 100),
  checklist      JSONB NOT NULL DEFAULT '{}',     
  signed_by_employee_at TIMESTAMPTZ,
  signed_by_issuer_id   BIGINT REFERENCES core.users(id),
  document_id    BIGINT,  
  client_uuid    UUID UNIQUE,                     
  FOREIGN KEY (company_id, vehicle_id)  REFERENCES fleet.vehicles (company_id, id),
  FOREIGN KEY (company_id, employee_id) REFERENCES core.employees (company_id, id),
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id),
  UNIQUE (company_id, id)
);

CREATE TABLE fleet.protocol_photos (      
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  protocol_id    BIGINT NOT NULL,
  document_id    BIGINT NOT NULL,
  damage_id      BIGINT,   
  caption        TEXT,
  FOREIGN KEY (company_id, protocol_id) REFERENCES fleet.protocols (company_id, id) ON DELETE CASCADE,
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id),
  FOREIGN KEY (company_id, damage_id) REFERENCES fleet.damages (company_id, id)
);
