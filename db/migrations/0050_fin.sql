-- Wygenerowane z docs/10-database-design.md i docs/16-platforma-integracji.md (tools/gen-migrations-from-docs.py).
-- Uzasadnienia kolumn i ograniczeń: w dokumentacji. Po wygenerowaniu plik edytuje się ręcznie — NIE generuje się go ponownie.

CREATE TABLE fin.fixed_assets (           
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
  event_id          BIGINT,                    
  event_occurred_at TIMESTAMPTZ,               
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

CREATE TABLE fin.postings (               
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        BIGINT NOT NULL REFERENCES core.companies(id),
  invoice_item_id   BIGINT,
  event_id          BIGINT,
  event_occurred_at TIMESTAMPTZ,
  account           TEXT NOT NULL,
  cost_center_id    BIGINT,
  branch_id         BIGINT,
  amount            NUMERIC(14,2) NOT NULL,
  period            DATE NOT NULL,             
  exported_at       TIMESTAMPTZ,
  FOREIGN KEY (company_id, event_id, event_occurred_at)
    REFERENCES fleet.events (company_id, id, occurred_at),
  FOREIGN KEY (company_id, cost_center_id) REFERENCES core.cost_centers (company_id, id),
  FOREIGN KEY (company_id, branch_id)      REFERENCES core.branches (company_id, id),
  FOREIGN KEY (company_id, invoice_item_id) REFERENCES fin.invoice_items (company_id, id) ON DELETE SET NULL (invoice_item_id)
);

CREATE INDEX ix_postings_period ON fin.postings (company_id, period);
