-- Wygenerowane z docs/10-database-design.md i docs/16-platforma-integracji.md (tools/gen-migrations-from-docs.py).
-- Uzasadnienia kolumn i ograniczeń: w dokumentacji. Po wygenerowaniu plik edytuje się ręcznie — NIE generuje się go ponownie.

CREATE TABLE docs.documents (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  kind           TEXT NOT NULL,           
  storage_key    TEXT NOT NULL,           
  mime_type      TEXT NOT NULL,
  size_bytes     BIGINT NOT NULL,
  sha256         TEXT NOT NULL,
  uploaded_by    BIGINT REFERENCES core.users(id),
  uploaded_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, sha256),             
  UNIQUE (company_id, id)
);

CREATE TABLE docs.ocr_results (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  document_id    BIGINT NOT NULL,
  layer          TEXT NOT NULL CHECK (layer IN ('aztec','ocr_service','vision_model')),
  fields         JSONB NOT NULL,
  raw_output     JSONB,
  fallback_reason TEXT,                   
  confirmed_by   BIGINT REFERENCES core.users(id),
  confirmed_at   TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  FOREIGN KEY (company_id, document_id) REFERENCES docs.documents (company_id, id) ON DELETE CASCADE
);
