# Platforma integracji: import, eksport, API, webhooki

FleetCore nie działa w próżni. U każdego klienta stoi już CRM, CFM, ERP, platforma flotowa, telematyka, system kart paliwowych — i te systemy zostają. FleetCore musi **przyjmować** z nich dane, **oddawać** im dane i **udostępniać API** innym podmiotom. Ten dokument opisuje jeden wspólny rdzeń, przez który idzie każda wymiana danych.

[Integracje API](04-api-integrations.md) opisują konkretne systemy zewnętrzne (KSeF, CEPiK, telematyka, karty). Ten dokument opisuje **mechanizm**, z którego wszystkie korzystają.

## Zasada

**Każda wymiana danych przechodzi przez ten sam rdzeń, niezależnie od kanału.** Plik, wywołanie API i webhook to trzy drogi do tych samych operacji: walidacja → mapowanie identyfikatorów → zapis zdarzenia → ślad audytowy. Nie ma „szybkiej ścieżki" importu omijającej walidację, którą stosuje interfejs.

Konsekwencje:

- reguły z [modelu danych](05-data-model-and-analytics.md) działają tak samo dla danych z pliku, z API i z ekranu: zero to brak danych, pola podatkowe mają pochodzenie, duplikaty blokuje klucz źródłowy;
- RLS i nadania spółek obowiązują także klienta API — klucz integracji jest przypisany do spółki tak samo jak użytkownik;
- każdy kanał zostawia ten sam ślad: kto (użytkownik albo klient API), co, ile rekordów, z jakim wynikiem.

---

## Cztery kanały

| Kanał | Kierunek | Dla kogo | Faza |
| --- | --- | --- | --- |
| **Pliki** — import i eksport | do i z FleetCore | każdy klient; systemy bez API (ZSI, Softra, Excel) | 1 |
| **API publiczne** — REST | do i z FleetCore | CRM, CFM, ERP, integratorzy, klienci budujący własne narzędzia | odczyt: 2; zapis: przed pierwszym klientem zewnętrznym |
| **Webhooki wychodzące** | z FleetCore | systemy, które chcą wiedzieć o zmianie od razu, bez odpytywania | przed pierwszym klientem zewnętrznym |
| **Konektory** — gotowe integracje z konkretnym systemem | zależnie od systemu | najczęstsze systemy klientów | na żądanie, od fazy 3 |

### 1. Pliki — import i eksport

Fundament. Działa z każdym systemem, także takim, który nigdy nie będzie miał API.

**Import**

- formaty: CSV (z wykrywaniem kodowania i separatora — patrz pułapka MyCar: „XLS", który jest TSV w UTF-16LE), XLSX, JSON;
- **mapowanie kolumn zapisane per system źródłowy i per najemca** (`integr.mappings`), wielokrotnego użytku — biblioteka mapowań z [onboardingu](14-onboarding-klienta.md);
- przebieg: wgranie → podgląd → walidacja → raport (wczytane, odrzucone z powodem, duplikaty) → zatwierdzenie → zapis;
- **przebieg próbny bez zapisu** jako domyślny pierwszy krok;
- import cykliczny: plik odbierany z katalogu SFTP albo z adresu e-mail importu, z tym samym mapowaniem — dla systemów, które umieją tylko wyeksportować plik o stałej porze (ZSI).

**Eksport**

- formaty: CSV, XLSX, JSON; dla księgowości — format wymagany przez ERP klienta (konfigurowalny szablon);
- eksport jednorazowy z każdej siatki i każdego raportu oraz **eksport cykliczny** (harmonogram, odbiorca: SFTP, e-mail, magazyn obiektowy);
- **pełny eksport danych najemcy** — przy odejściu klienta ([onboarding](14-onboarding-klienta.md));
- eksport jest zdarzeniem bezpieczeństwa: ślad audytowy, alert powyżej 10 000 wierszy ([bezpieczeństwo](06-security-privacy-compliance.md)).

### 2. API publiczne

To samo API, którego używa panel i aplikacja mobilna ([integracje](04-api-integrations.md), „Wewnętrzne API"), udostępnione podmiotom zewnętrznym z innym sposobem uwierzytelniania i z zakresami uprawnień.

| Element | Rozwiązanie |
| --- | --- |
| Styl | REST + JSON, kontrakt OpenAPI 3.1 publikowany pod `/v1/openapi.json` i jako dokumentacja dla integratorów |
| Uwierzytelnianie | **OAuth 2.0 client credentials** — klient integracji dostaje `client_id` i sekret, wymienia je na krótkotrwały token. Dla prostych integracji: klucz API (nagłówek), z tymi samymi zakresami. Sekret widoczny raz, przy utworzeniu; w bazie tylko skrót |
| Przypisanie | klient integracji należy do **jednej spółki** i ma **zakresy** (`vehicles:read`, `events:write`, `tax:read`, `finance:export`…). Brak zakresu = odmowa, nie pusta odpowiedź |
| Wersjonowanie | ścieżka `/v1/…`; zmiana niezgodna wstecz = `/v2`; stara wersja żyje minimum 12 miesięcy po ogłoszeniu wycofania |
| Identyfikatory | zewnętrzny system może posługiwać się **własnymi identyfikatorami** — mapowanie w `integr.external_refs` (np. `PUT /v1/vehicles/by-external/crm/{id}`) |
| Idempotencja | nagłówek `Idempotency-Key` obowiązkowy dla zapisów; powtórzone żądanie zwraca ten sam wynik zamiast tworzyć duplikat |
| Stronicowanie | kursor; plus `updated_since` do synchronizacji przyrostowej — system zewnętrzny pobiera tylko zmiany |
| Limity | per klient integracji (np. 600 żądań/min), z nagłówkami informującymi o limicie; 429 z `Retry-After` |
| Błędy | RFC 9457 (`application/problem+json`), z polem wskazującym błędne pole wejścia |
| Środowisko testowe | integrator dostaje klienta API w środowisku `demo` — z przykładową flotą, bez danych produkcyjnych |

**Czego API nie robi:** nie omija reguł domenowych. Pole podatkowe zapisane przez API wymaga wskazania źródła i trafia do pochodzenia pól z rangą przypisaną temu klientowi integracji; zapis do spółki spoza nadania kończy się odmową RLS.

### 3. Webhooki wychodzące

System zewnętrzny rejestruje adres i listę zdarzeń; FleetCore wysyła powiadomienie po zatwierdzeniu transakcji (przez `integr.outbox`).

- zdarzenia: `vehicle.created`, `vehicle.updated`, `event.created` (z typem: tankowanie, szkoda…), `reminder.due`, `damage.reported`, `declaration.ready`, `invoice.exported`, `import.completed`…;
- **podpis HMAC-SHA256** każdej wiadomości sekretem subskrypcji, ze znacznikiem czasu — odbiorca weryfikuje, że wiadomość jest od nas i nie jest powtórką;
- ponawianie z wykładniczym odstępem do 24 h; potem wiadomość w „martwej kolejce" widocznej dla administratora najemcy i **alert** — cicho porzucone powiadomienie to ta sama klasa błędu co cicho rosnąca kolejka KSeF;
- treść: identyfikator i typ zdarzenia + minimum danych; pełne dane odbiorca pobiera przez API swoim tokenem (dane osobowe nie krążą w powiadomieniach).

### 4. Konektory

Gotowa integracja z konkretnym systemem = **konfiguracja kanałów 1–3**, nie osobny kod omijający rdzeń. Konektor dostarcza: mapowanie pól, harmonogram, sposób uwierzytelnienia u dostawcy i testy kontraktowe.

| Kategoria | Przykłady | Typowy kierunek | Kanał startowy |
| --- | --- | --- | --- |
| **ERP / FK** | **ZSI**, Comarch, enova365, Symfonia, SAP | do ERP: dekrety, dokumenty kosztowe; z ERP: kartoteki, kontrahenci | pliki |
| **CRM** | HubSpot, Salesforce, Pipedrive, Livespace | z CRM: klienci i umowy najmu; do CRM: status pojazdu, rezerwacje | API + webhooki |
| **CFM / leasing** | systemy leasingodawców i firm CFM | z CFM: umowy, harmonogramy rat, limity przebiegu; do CFM: przebiegi, szkody | pliki, potem API |
| **Platformy flotowe, telematyka** | MyCar, dostawcy GPS | do FleetCore: przebiegi, pozycje, e-TOLL | API dostawcy / pliki |
| **Karty paliwowe** | ORLEN Flota i inni | do FleetCore: transakcje, statusy kart | pliki |
| **Systemy flotowe konkurencji (migracja)** | Softra, PasCom, CARMEN | jednorazowo do FleetCore | pliki eksportu |

Konektory budujemy **na żądanie klienta**, w kolejności popularności — nie „na zapas". Każdy klient z nowym systemem zaczyna od kanału plikowego, który działa od pierwszego dnia.

---

## ZSI — decyzja na teraz

**Integracja z ZSI wyłącznie przez eksport plików.** Rozmowa o API ZSI — w późniejszym terminie.

- **ZSI → FleetCore:** eksport z ZSI (pojazdy, kierowcy, norma EURO, przebiegi, polisy) wczytywany przez import z zapisanym mapowaniem; docelowo cyklicznie (plik odbierany z katalogu albo e-mailem).
- **FleetCore → ZSI:** eksport dekretów i dokumentów kosztowych w formacie importu ZSI; status `exported` do czasu potwierdzenia przez księgowość, że dokument wszedł do ZSI ([systemy odniesienia](12-source-systems.md), rozdział 5).
- **Bez** bezpośredniego odczytu bazy ZSI, bez zapisu do niej. Istniejący most `tools/zsia-sync.ps1` z TaxOrder Pro jest materiałem poglądowym (jakie pola i skąd), nie wzorcem integracji.

---

## Model danych platformy

Uzupełnia schemat `integr` z [projektu bazy](10-database-design.md).

```sql
-- Klient integracji (system zewnętrzny) — odpowiednik użytkownika dla API
CREATE TABLE integr.api_clients (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  name           TEXT NOT NULL,                 -- np. 'HubSpot – dział najmu'
  client_id      TEXT NOT NULL UNIQUE,
  secret_hash    TEXT NOT NULL,                 -- sekret pokazany raz; w bazie tylko skrót
  scopes         TEXT[] NOT NULL,               -- {'vehicles:read','events:write',...}
  source_rank_as TEXT CHECK (source_rank_as IN
                   ('manual','registration_doc','erp','fleet_platform','fuel_import','cep')),
                                                -- jaką rangę mają pola zapisane przez tego klienta
  rate_limit_per_min INT NOT NULL DEFAULT 600,
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_by     BIGINT REFERENCES core.users(id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at   TIMESTAMPTZ,
  UNIQUE (company_id, id)
);

-- Identyfikatory obcych systemów przypisane do encji FleetCore
CREATE TABLE integr.external_refs (
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  system         TEXT NOT NULL,                 -- 'zsi','hubspot','mycar',...
  entity         TEXT NOT NULL CHECK (entity IN
                   ('vehicle','employee','partner','contract','policy','invoice','event')),
  external_id    TEXT NOT NULL,
  internal_id    BIGINT NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (company_id, system, entity, external_id),
  UNIQUE (company_id, system, entity, internal_id)
);

-- Mapowania kolumn importu/eksportu, wielokrotnego użytku
CREATE TABLE integr.mappings (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT REFERENCES core.companies(id),   -- NULL = mapowanie z biblioteki (np. Softra)
  system         TEXT NOT NULL,
  direction      TEXT NOT NULL CHECK (direction IN ('import','export')),
  entity         TEXT NOT NULL,
  version        INT NOT NULL DEFAULT 1,
  definition     JSONB NOT NULL,                -- kolumna źródłowa → pole, konwersje, kodowanie
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (company_id, system, direction, entity, version)
);

-- Zadania importu i eksportu (pliki, harmonogramy, pełny eksport najemcy)
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

-- Subskrypcje webhooków i dostarczenia
CREATE TABLE integr.webhook_subscriptions (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     BIGINT NOT NULL REFERENCES core.companies(id),
  url            TEXT NOT NULL CHECK (url LIKE 'https://%'),
  events         TEXT[] NOT NULL,
  secret_ref     TEXT NOT NULL,                 -- sekret HMAC w magazynie sekretów
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
  dead_at        TIMESTAMPTZ,                   -- po wyczerpaniu ponowień: alert, widoczne dla admina
  FOREIGN KEY (company_id, subscription_id)
    REFERENCES integr.webhook_subscriptions (company_id, id) ON DELETE CASCADE
);
```

Wszystkie tabele z `company_id` dostają polityki RLS jak każda tabela najemcy. Biblioteka mapowań (`company_id IS NULL`) jest czytelna dla wszystkich, zapisywalna tylko z migracji — jak słowniki systemowe.

---

## Bezpieczeństwo i RODO

- **Klient API to podmiot, któremu klient FleetCore udostępnia dane.** Odpowiedzialność za to, komu nadaje klucz i jakie zakresy, ponosi administrator najemcy — panel pokazuje przy tworzeniu klucza, do jakich danych osobowych dają dostęp wybrane zakresy.
- Zakresy dotyczące danych lokalizacyjnych (`telematics:read`) wymagają osobnego potwierdzenia administratora i trafiają do audytu przy każdym użyciu — jak flaga `can_view_routes` u użytkownika.
- Sekrety klientów API i webhooków: pokazane raz, w bazie skrót albo odwołanie do magazynu sekretów; rotacja bez przerwy w działaniu (dwa ważne sekrety przez okres przejściowy).
- Unieważnienie klucza działa natychmiast; lista kluczy z datą ostatniego użycia w panelu administratora.
- Webhooki tylko na `https://`; adresy w sieciach prywatnych odrzucane (ochrona przed SSRF).

---

## Kolejność budowy

| Faza | Co z platformy |
| --- | --- |
| 1 | import plików z mapowaniami, przebieg próbny, raport; eksport CSV/XLSX z siatek; `integr.jobs`, `integr.mappings` |
| 2 | eksport do FK w formacie ZSI; API publiczne **tylko do odczytu** z OAuth client credentials i zakresami; `integr.external_refs` |
| Przed pierwszym klientem zewnętrznym | API z zapisem i idempotencją, webhooki z podpisem, pełny eksport najemcy, dokumentacja dla integratorów, klient API w `demo` |
| Od fazy 3, na żądanie | konektory: CRM, CFM, kolejne ERP; import cykliczny SFTP/e-mail |
