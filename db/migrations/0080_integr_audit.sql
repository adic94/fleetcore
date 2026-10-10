-- Wygenerowane z docs/10-database-design.md i docs/16-platforma-integracji.md (tools/gen-migrations-from-docs.py).
-- Uzasadnienia kolumn i ograniczeń: w dokumentacji. Po wygenerowaniu plik edytuje się ręcznie — NIE generuje się go ponownie.

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

CREATE TABLE audit.audit_logs (
  id             BIGINT GENERATED ALWAYS AS IDENTITY,
  company_id     BIGINT REFERENCES core.companies(id),
  user_id        BIGINT REFERENCES core.users(id),
  occurred_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  action         TEXT NOT NULL,           
  entity         TEXT NOT NULL,
  entity_id      BIGINT,
  before         JSONB,
  after          JSONB,
  ip             INET,
  row_count      INT,                     
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE integr.api_clients (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  name           TEXT NOT NULL,                 
  client_id      TEXT NOT NULL UNIQUE,
  secret_hash    TEXT NOT NULL,                 
  scopes         TEXT[] NOT NULL,               
  source_rank_as TEXT CHECK (source_rank_as IN
                   ('manual','registration_doc','erp','fleet_platform','fuel_import','cep')),
                                                
  rate_limit_per_min INT NOT NULL DEFAULT 600,
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_by     BIGINT REFERENCES core.users(id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at   TIMESTAMPTZ,
  UNIQUE (company_id, id)
);

CREATE TABLE integr.external_refs (
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  system         TEXT NOT NULL,                 
  entity         TEXT NOT NULL CHECK (entity IN
                   ('vehicle','employee','partner','contract','policy','invoice','event')),
  external_id    TEXT NOT NULL,
  internal_id    BIGINT NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (company_id, system, entity, external_id),
  UNIQUE (company_id, system, entity, internal_id)
);

CREATE TABLE integr.mappings (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT REFERENCES core.companies(id),   
  system         TEXT NOT NULL,
  direction      TEXT NOT NULL CHECK (direction IN ('import','export')),
  entity         TEXT NOT NULL,
  version        INT NOT NULL DEFAULT 1,
  definition     JSONB NOT NULL,                
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (company_id, system, direction, entity, version)
);

CREATE TABLE integr.jobs (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  kind           TEXT NOT NULL CHECK (kind IN ('import','export','full_export')),
  mapping_id     BIGINT REFERENCES integr.mappings(id),
  dry_run        BOOLEAN NOT NULL DEFAULT TRUE,
  status         TEXT NOT NULL DEFAULT 'queued'
                   CHECK (status IN ('queued','running','succeeded','failed','cancelled')),
  requested_by_user   BIGINT REFERENCES core.users(id),
  requested_by_client BIGINT,
  source_document_id  BIGINT,
  result_document_id  BIGINT,
  rows_total     INT,
  rows_ok        INT,
  rows_rejected  INT,
  rows_duplicate INT,
  error          TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at    TIMESTAMPTZ,
  FOREIGN KEY (company_id, requested_by_client) REFERENCES integr.api_clients (company_id, id),
  FOREIGN KEY (company_id, source_document_id) REFERENCES docs.documents (company_id, id),
  FOREIGN KEY (company_id, result_document_id) REFERENCES docs.documents (company_id, id)
);

CREATE TABLE integr.webhook_subscriptions (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  url            TEXT NOT NULL CHECK (url LIKE 'https://%'),
  events         TEXT[] NOT NULL,
  secret_ref     TEXT NOT NULL,                 
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_by     BIGINT REFERENCES core.users(id),
  UNIQUE (company_id, id)
);

CREATE TABLE integr.webhook_deliveries (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  subscription_id BIGINT NOT NULL,
  event_type     TEXT NOT NULL,
  payload        JSONB NOT NULL,
  attempts       SMALLINT NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_status    INT,
  delivered_at   TIMESTAMPTZ,
  dead_at        TIMESTAMPTZ,                   
  FOREIGN KEY (company_id, subscription_id)
    REFERENCES integr.webhook_subscriptions (company_id, id) ON DELETE CASCADE
);
