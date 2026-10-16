# Diagramy ERD PostgreSQL

Diagramy w składni Mermaid — renderują się w podglądzie Markdown w IDE i na GitHubie. Definicje kolumn: [projekt bazy danych](10-database-design.md).

Na diagramach pominięto kolumny audytowe (`created_at`, `created_by`, `updated_at`, `updated_by`) oraz `company_id`, które występuje **w każdej tabeli danych klienta** i jest częścią każdego klucza obcego między tabelami najemcy (`(company_id, x_id) → (company_id, id)`, patrz konwencja 9 w [projekcie bazy](10-database-design.md)).

## Mapa schematów

```mermaid
flowchart TD
    CORE[core<br/>najemcy, użytkownicy, słowniki]
    FLEET[fleet<br/>pojazdy, zdarzenia, rejestry]
    TAX[tax<br/>DT-1, stawki, opłata środowiskowa]
    FIN[fin<br/>faktury, dekrety, środki trwałe]
    RENT[rent<br/>cenniki, rezerwacje, najem]
    TMS[tms<br/>zlecenia transportowe]
    DOCS[docs<br/>dokumenty, OCR]
    TELE[telematics<br/>pozycje, jazdy prywatne]
    ASSETS[assets<br/>wyposażenie, oświadczenia]
    INTEGR[integr<br/>klienci integracji]
    AUDIT[audit<br/>ślad audytowy]

    CORE --> FLEET
    CORE --> FIN
    CORE --> RENT
    CORE --> TMS
    FLEET --> TAX
    FLEET --> FIN
    FLEET --> RENT
    FLEET --> TMS
    DOCS --> FLEET
    DOCS --> FIN
    DOCS --> TAX
    TELE --> FLEET
    INTEGR --> FLEET
    INTEGR --> FIN
    CORE --> ASSETS
    DOCS --> ASSETS
```

Strzałka oznacza kierunek zależności: `tax` czyta z `fleet`, nigdy odwrotnie. Zależność cykliczna między schematami jest zabroniona — wymuszane uprawnieniami ról bazodanowych, nie tylko przeglądem kodu.

## core — najemcy i ludzie

```mermaid
erDiagram
    companies ||--o{ user_company_access : "nadaje dostęp"
    users ||--o{ user_company_access : "ma dostęp"
    companies ||--o{ company_modules : "licencje modułów"
    companies ||--o{ branches : "ma"
    companies ||--o{ cost_centers : "ma"
    companies ||--o{ partners : "ma"
    companies ||--o{ employees : "zatrudnia"
    users ||--o| employees : "konto pracownika"
    branches ||--o{ employees : "przypisanie"
    cost_centers ||--o{ cost_centers : "nadrzędne MPK"
    companies ||--o{ addresses : "ma"
    addresses ||--o{ branches : "adres"
    companies ||--o{ field_definitions : "pola rozszerzalne"
    companies ||--o{ report_definitions : "raporty"

    companies {
        bigint id PK
        text code UK
        text name
        text nip
        boolean active
    }
    users {
        bigint id PK
        text email UK
        text external_sub UK
        text platform_role
        boolean mfa_enabled
    }
    user_company_access {
        bigint id PK
        bigint user_id FK
        bigint company_id FK
        text role
        boolean can_view_routes
        bigint granted_by FK
        timestamptz granted_at
    }
    company_modules {
        bigint id PK
        bigint company_id FK
        text module_code
        boolean enabled
        date valid_from
        date valid_to
    }
    employees {
        bigint id PK
        bigint user_id FK
        bigint branch_id FK
        bigint cost_center_id FK
        text personal_no
        date hired_on
    }
    partners {
        bigint id PK
        text name
        text nip
        text_array kind
    }
```

**`user_company_access` to sedno modelu uprawnień.** Dostęp do spółki jest wierszem, który widać i który da się odebrać — nie właściwością roli. Rola też jest per spółka: ta sama osoba może być księgową w jednej spółce i przeglądającym w drugiej. To odpowiedź na dług z poprzedniego systemu, gdzie rola administratora pomijała filtrowanie wszędzie i nie było jak tego ograniczyć.

## fleet — pojazd i jego oś czasu

```mermaid
erDiagram
    vehicles ||--o{ vehicle_plates : "historia tablic"
    vehicles ||--o{ vehicle_field_provenance : "pochodzenie pól"
    vehicles ||--o{ events : "oś czasu"
    vehicles ||--o{ contracts : "umowy"
    vehicles ||--o{ policies : "polisy"
    vehicles ||--o{ damages : "szkody"
    vehicles ||--o{ odometer_readings : "liczniki"
    vehicles ||--o{ fines : "mandaty"
    vehicles ||--o{ tires : "opony"
    vehicles ||--o{ reminders : "terminy"
    contracts ||--o{ contract_schedule : "raty"
    policies ||--o{ damages : "likwidacja z polisy"
    fuel_cards ||--o{ fuel_card_assignments : "przypisania"
    vehicles ||--o{ fuel_card_assignments : "karta na pojeździe"
    authorizations ||--o{ authorization_items : "pozycje"
    vehicles ||--o{ authorizations : "zgody na naprawy"
    vehicles ||--o{ vehicle_assignments : "przypisania w czasie"
    vehicles ||--o{ protocols : "wydanie, zdanie, oględziny"
    protocols ||--o{ protocol_photos : "zdjęcia"
    vehicles ||--o{ data_conflicts : "do rozstrzygnięcia"
    events ||--o| event_source_keys : "klucz deduplikacji"

    vehicles {
        bigint id PK
        text vin UK
        text plate
        text homolog_category
        numeric dmc_kg
        smallint axles_count
        text suspension_type
        text fuel_type
        text status
        jsonb extra
    }
    vehicle_plates {
        bigint id PK
        bigint vehicle_id FK
        text plate
        date valid_from
        date valid_to
    }
    vehicle_field_provenance {
        bigint id PK
        bigint vehicle_id FK
        text field_name
        text source
        smallint rank
        bigint document_id FK
    }
    events {
        bigint id PK
        bigint vehicle_id FK
        text kind
        timestamptz occurred_at
        numeric amount_net
        text source
        text external_ref
    }
    contracts {
        bigint id PK
        bigint partner_id FK
        text kind
        text number
        date start_date
        date end_date
        int mileage_limit
    }
    policies {
        bigint id PK
        bigint insurer_id FK
        text number
        date valid_from
        date valid_to
        numeric premium_gross
    }
```

Trzy rzeczy, które ten diagram ma unaocznić:

1. **`vin` jest unikalne, `plate` nie.** Numer rejestracyjny mieszka w `vehicle_plates` z zakresem dat i ograniczeniem wykluczającym nakładanie się okresów.
2. **`events` jest jedną tabelą dla wszystkich typów zdarzeń**, a nie osobną tabelą na tankowania, osobną na naprawy i osobną na mandaty. Rejestry obok (`policies`, `damages`, `contracts`) trzymają dane **strukturalne**, kwoty i daty trafiają do `events`.
3. **`vehicle_field_provenance` wisi obok `vehicles`**, a nie w środku. Kartoteka trzyma wartość obowiązującą, tabela obok — wszystkie warianty z rangami i wskazaniem dokumentu.

## tax — podatek od środków transportowych

```mermaid
erDiagram
    municipalities ||--o{ rate_sets : "uchwały"
    rate_sets ||--o{ rates : "pozycje stawek"
    municipalities ||--o{ declarations : "właściwy organ"
    declarations ||--o{ declaration_lines : "pozycje"
    declarations ||--o| declarations : "korekta"
    vehicles ||--o{ declaration_lines : "opodatkowany"
    rates ||--o{ declaration_lines : "zastosowana stawka"

    municipalities {
        bigint id PK
        text teryt UK
        text name
    }
    rate_sets {
        bigint id PK
        bigint municipality_id FK
        int year
        text resolution_no
        date verified_at
        int verified_positions
    }
    rates {
        bigint id PK
        bigint rate_set_id FK
        text category_code
        text vehicle_kind
        text mass_basis
        numeric dmc_min_kg
        numeric dmc_max_kg
        smallint axles_min
        smallint axles_max
        text suspension
        smallint seats_min
        text fuel_group
        numeric amount_pln
    }
    declarations {
        bigint id PK
        int year
        text form
        text status
        bigint correction_of FK
        numeric total_amount_pln
        timestamptz filed_at
    }
    declaration_lines {
        bigint id PK
        bigint vehicle_id FK
        bigint rate_id FK
        text category_code
        smallint months_owned
        numeric amount_pln
        text exemption
        text_array blocking_fields
    }
```

`declaration_lines.rate_id` wskazuje **konkretną pozycję konkretnej uchwały**. Bez tego złożona deklaracja jest nieodtwarzalna: za trzy lata nikt nie ustali, czy kwota wynikała z uchwały, czy z pomyłki. `rate_sets.verified_positions` mówi, ile pozycji faktycznie porównano ze źródłem — dla Warszawy 2026 jest to 45 z 45.

## fin — od faktury do dekretu

```mermaid
erDiagram
    partners ||--o{ invoices : "kontrahent"
    invoices ||--o{ invoice_items : "pozycje"
    invoice_items ||--o{ postings : "dekrety"
    vehicles ||--o{ invoice_items : "koszt pojazdu"
    cost_centers ||--o{ postings : "MPK"
    branches ||--o{ postings : "oddział"
    vehicles ||--o| fixed_assets : "środek trwały"
    fixed_assets ||--o{ depreciation : "odpisy"
    documents ||--o| invoices : "skan"

    invoices {
        bigint id PK
        text direction
        bigint partner_id FK
        text number
        date issue_date
        numeric net_total
        numeric vat_total
        text ksef_ref
        text ksef_status
    }
    invoice_items {
        bigint id PK
        bigint invoice_id FK
        bigint vehicle_id FK
        bigint event_id FK
        numeric net_amount
        numeric vat_rate
        smallint vat_deduction_pct
    }
    postings {
        bigint id PK
        bigint invoice_item_id FK
        text account
        bigint cost_center_id FK
        numeric amount
        date period
        timestamptz exported_at
    }
    fixed_assets {
        bigint id PK
        bigint vehicle_id FK
        text inventory_no UK
        numeric initial_value
        text method
        numeric rate_pct
    }
```

Ścieżka `invoice_items → event_id` jest tym, co likwiduje podwójne wprowadzanie danych: pozycja faktury za paliwo wskazuje na **to samo zdarzenie**, które widzi kartoteka pojazdu i raport zużycia. Dziś ta sama informacja istnieje osobno w systemie flotowym i osobno w księgowym.

## rent — najem

```mermaid
erDiagram
    price_lists ||--o{ price_list_items : "pozycje"
    partners ||--o{ price_lists : "cennik indywidualny"
    reservations ||--o| orders : "realizacja"
    vehicles ||--o{ reservations : "rezerwowany"
    vehicles ||--o{ orders : "wydany"
    partners ||--o{ orders : "najemca"

    price_lists {
        bigint id PK
        text name
        date valid_from
        date valid_to
        bigint partner_id FK
    }
    price_list_items {
        bigint id PK
        text vehicle_group
        text period_unit
        numeric price_net
        int mileage_incl
        numeric extra_km_net
    }
    reservations {
        bigint id PK
        bigint vehicle_id FK
        timestamptz starts_at
        timestamptz ends_at
        text status
    }
    orders {
        bigint id PK
        bigint reservation_id FK
        bigint vehicle_id FK
        int mileage_out
        int mileage_in
        numeric deposit_amount
        text status
    }
```

## tms — zlecenia transportowe

```mermaid
erDiagram
    partners ||--o{ tms_orders : "zleceniodawca"
    vehicles ||--o{ tms_orders : "pojazd"
    vehicles ||--o{ tms_orders : "naczepa (trailer_id)"
    employees ||--o{ tms_orders : "kierowca"
    tms_orders ||--o{ order_stops : "punkty trasy"
    tms_orders ||--o{ transport_docs : "dokumenty"
    documents ||--o| transport_docs : "plik"

    tms_orders {
        bigint id PK
        text number UK
        text kind
        bigint customer_id FK
        bigint vehicle_id FK
        bigint driver_id FK
        numeric freight_net
        text status
    }
    order_stops {
        bigint id PK
        int seq
        text kind
        bigint address_id FK
        timestamptz planned_at
        timestamptz actual_at
    }
    transport_docs {
        bigint id PK
        text kind
        text number
        bigint document_id FK
    }
```

Pojazd i naczepa wskazują na **tę samą tabelę** `fleet.vehicles` — naczepa jest pojazdem z rodzajem „przyczepa", a nie osobną encją. To istotne podatkowo: przyczepa i naczepa podlegają DT-1, gdy łącznie z pojazdem silnikowym mają DMC od 7 t, i mają własną tabelę stawek, inną niż samochód ciężarowy.

## docs i OCR

```mermaid
erDiagram
    documents ||--o{ ocr_results : "warstwy kaskady"
    documents ||--o{ vehicle_field_provenance : "źródło pola"
    users ||--o| ocr_results : "zatwierdził"

    documents {
        bigint id PK
        text kind
        text storage_key
        text sha256 UK
        bigint uploaded_by FK
    }
    ocr_results {
        bigint id PK
        bigint document_id FK
        text layer
        jsonb fields
        jsonb raw_output
        text fallback_reason
        bigint confirmed_by FK
    }
```

Jeden dokument ma **wiele** wierszy `ocr_results` — po jednym na warstwę kaskady. `fallback_reason` odpowiada na pytanie, dlaczego zadziałała warstwa niższa. Bez tego pola awaria warstwy wyższej objawia się jako gorsze dane, nie jako błąd; dokładnie ta klasa problemu kosztowała dwie diagnozy w poprzednim systemie.

`documents.sha256` jest unikalne w ramach najemcy — ten sam plik nie wchodzi dwa razy.

## Partycjonowanie

```mermaid
flowchart LR
    E[fleet.events] --> E1[events_2026_01]
    E --> E2[events_2026_02]
    E --> E3[...]
    P[telematics.positions] --> P1[positions_2026_01]
    P --> P2[...]
    A[audit.audit_logs] --> A1[audit_2026_01]
    A --> A2[...]
```

Trzy tabele rosnące bez ograniczeń są partycjonowane miesięcznie po dacie zdarzenia. Partycje tworzy zadanie cykliczne z wyprzedzeniem, a nie mechanizm reagujący na pierwszy nieudany zapis.

Retencja przez odłączanie partycji: pozycje GPS starsze niż 12 miesięcy są odłączane i archiwizowane po zbudowaniu agregatów dobowych. Odłączenie partycji jest natychmiastowe; kasowanie wierszy przy tej skali nie jest.


## DANE WSADOWE !! DO ZROBIENIA

## DANE KIEROWCÓW









