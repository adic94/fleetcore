-- Wygenerowane z docs/10-database-design.md i docs/16-platforma-integracji.md (tools/gen-migrations-from-docs.py).
-- Uzasadnienia kolumn i ograniczeń: w dokumentacji. Po wygenerowaniu plik edytuje się ręcznie — NIE generuje się go ponownie.

CREATE TABLE core.companies (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code           TEXT NOT NULL UNIQUE,          
  name           TEXT NOT NULL,
  nip            TEXT,
  regon          TEXT,
  street         TEXT,                          
  postal_code    TEXT,                          
  city           TEXT,                          
  teryt          TEXT,                          
  lifecycle      TEXT NOT NULL DEFAULT 'onboarding'
                   CHECK (lifecycle IN ('onboarding','active','offboarding','closed')),
                                                
                                                
                                                
                                                
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE core.users (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email          TEXT NOT NULL UNIQUE,
  password_hash  TEXT,
  external_sub   TEXT UNIQUE,                   
  full_name      TEXT NOT NULL,
  platform_role  TEXT NOT NULL DEFAULT 'user'
                   CHECK (platform_role IN ('superadmin','user')),  
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  mfa_enabled    BOOLEAN NOT NULL DEFAULT FALSE,
  mfa_secret_ref TEXT,                          
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE core.user_company_access (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id        BIGINT NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  role           TEXT NOT NULL CHECK (role IN
                   ('admin','manager','dispatcher','accountant','driver','viewer')),
  can_view_routes BOOLEAN NOT NULL DEFAULT FALSE,   
  is_implementer BOOLEAN NOT NULL DEFAULT FALSE,    
                                                    
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

CREATE TABLE core.branches (              
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  code           TEXT NOT NULL,
  name           TEXT NOT NULL,
  address_id     BIGINT,
  UNIQUE (company_id, code),
  UNIQUE (company_id, id),
  FOREIGN KEY (company_id, address_id) REFERENCES core.addresses (company_id, id)
);

CREATE TABLE core.cost_centers (          
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

CREATE TABLE core.partners (              
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  name           TEXT NOT NULL,
  nip            TEXT,
  kind           TEXT[] NOT NULL,               
  address_id     BIGINT,
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (company_id, id),
  FOREIGN KEY (company_id, address_id) REFERENCES core.addresses (company_id, id)
);

CREATE TABLE core.employees (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  user_id        BIGINT REFERENCES core.users(id),   
  first_name     TEXT NOT NULL,
  last_name      TEXT NOT NULL,
  personal_no    TEXT,                          
  branch_id      BIGINT,
  cost_center_id BIGINT,
  hired_on       DATE,
  left_on        DATE,
  deleted_at     TIMESTAMPTZ,
  UNIQUE (company_id, id),
  FOREIGN KEY (company_id, branch_id)      REFERENCES core.branches (company_id, id),
  FOREIGN KEY (company_id, cost_center_id) REFERENCES core.cost_centers (company_id, id)
);

CREATE TABLE core.dictionaries (          
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT REFERENCES core.companies(id),  
  kind           TEXT NOT NULL,                 
  code           TEXT NOT NULL,
  label          TEXT NOT NULL,
  sort_order     INT NOT NULL DEFAULT 0,
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE NULLS NOT DISTINCT (company_id, kind, code)   
);

CREATE TABLE core.field_definitions (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  entity         TEXT NOT NULL CHECK (entity IN ('vehicle','employee','contract','policy')),
  key            TEXT NOT NULL CHECK (key ~ '^[a-z][a-z0-9_]{1,62}$'),  
  label          TEXT NOT NULL,
  data_type      TEXT NOT NULL CHECK (data_type IN ('text','number','date','bool','dictionary')),
  dictionary_kind TEXT,                         
  in_grid        BOOLEAN NOT NULL DEFAULT TRUE,
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (company_id, entity, key)
);

CREATE TABLE core.report_definitions (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  user_id        BIGINT REFERENCES core.users(id),   
  code           TEXT NOT NULL,                      
  name           TEXT NOT NULL,
  columns        JSONB NOT NULL,                     
  filters        JSONB NOT NULL DEFAULT '{}',
  sort           JSONB NOT NULL DEFAULT '[]',
  group_by       JSONB NOT NULL DEFAULT '[]',
  UNIQUE NULLS NOT DISTINCT (company_id, user_id, code)
);

CREATE TABLE core.company_modules (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  module_code    TEXT NOT NULL,            
  enabled        BOOLEAN NOT NULL DEFAULT TRUE,
  valid_from     DATE NOT NULL DEFAULT CURRENT_DATE,
  valid_to       DATE,
  granted_by     BIGINT REFERENCES core.users(id),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, module_code)
);

CREATE TABLE core.source_ranks (
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  source         TEXT NOT NULL CHECK (source IN
                   ('manual','registration_doc','erp','fleet_platform','fuel_import','cep')),
  rank           SMALLINT NOT NULL CHECK (rank BETWEEN 1 AND 9),
  system_name    TEXT,                    
  PRIMARY KEY (company_id, source)
);
