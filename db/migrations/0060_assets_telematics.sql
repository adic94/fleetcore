-- Wygenerowane z docs/10-database-design.md i docs/16-platforma-integracji.md (tools/gen-migrations-from-docs.py).
-- Uzasadnienia kolumn i ograniczeń: w dokumentacji. Po wygenerowaniu plik edytuje się ręcznie — NIE generuje się go ponownie.

CREATE TABLE telematics.positions (
  id             BIGINT GENERATED ALWAYS AS IDENTITY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  vehicle_id     BIGINT NOT NULL,
  recorded_at    TIMESTAMPTZ NOT NULL,
  lat            NUMERIC(9,6),
  lon            NUMERIC(9,6),
  speed_kmh      NUMERIC(6,2),
  ignition       BOOLEAN,
  engine_rpm     INT,                     
  PRIMARY KEY (id, recorded_at),
  FOREIGN KEY (company_id, vehicle_id) REFERENCES fleet.vehicles (company_id, id)
) PARTITION BY RANGE (recorded_at);

CREATE TABLE telematics.private_trips (    
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

CREATE TABLE assets.items (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  kind           TEXT NOT NULL CHECK (kind IN ('phone','sim','laptop','card','clothing','tool','other')),
  name           TEXT NOT NULL,
  serial_no      TEXT,
  phone_number   TEXT,                    
  monthly_limit  NUMERIC(14,2),
  status         TEXT NOT NULL DEFAULT 'in_stock'
                   CHECK (status IN ('in_stock','issued','repair','lost','scrapped')),
  UNIQUE (company_id, id)
);

CREATE TABLE assets.issues (               
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

CREATE TABLE assets.statements (           
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
