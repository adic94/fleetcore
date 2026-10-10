-- Wygenerowane z docs/10-database-design.md i docs/16-platforma-integracji.md (tools/gen-migrations-from-docs.py).
-- Uzasadnienia kolumn i ograniczeń: w dokumentacji. Po wygenerowaniu plik edytuje się ręcznie — NIE generuje się go ponownie.

CREATE TABLE rent.price_lists (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  name           TEXT NOT NULL,
  valid_from     DATE NOT NULL,
  valid_to       DATE,
  partner_id     BIGINT,   
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

CREATE TABLE rent.orders (                
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
  kind           TEXT NOT NULL,           
  number         TEXT,
  document_id    BIGINT,
  FOREIGN KEY (company_id, order_id) REFERENCES tms.orders (company_id, id) ON DELETE CASCADE,
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id)
);
