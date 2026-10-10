# Architektura i stack techniczny

## Warstwy

    przeglądarka / aplikacja mobilna
            |
        API (REST, OpenAPI)
            |
    +-------+--------+--------+---------+
    | Flota | Rent   | Transp.| Finanse |   moduły domenowe
    +-------+--------+--------+---------+
            |
       magistrala zdarzeń (outbox + kolejka)
            |
    +----------+-----------+-------------+
    | Postgres | S3/MinIO  | OCR (Python)|
    +----------+-----------+-------------+

## Decyzje architektoniczne

### 1. Modularny monolit, nie mikroserwisy

Jedna aplikacja NestJS z twardymi granicami modułów. Moduł komunikuje się z innym wyłącznie przez interfejs publiczny i zdarzenia, **nigdy przez cudzą tabelę**.

**Dlaczego nie mikroserwisy:** domena jest mocno powiązana — koszt pojazdu dotyka jednocześnie floty, finansów i podatków. Rozbicie na serwisy oznacza transakcje rozproszone tam, gdzie wystarczy transakcja bazodanowa. Przy zespole 3–4 osób koszt utrzymania infrastruktury mikroserwisowej przewyższa korzyść.

Granice modułów zostają ostre, żeby wydzielenie było możliwe później — ale dopiero gdy okaże się potrzebne, a nie „na wszelki wypadek".

### 2. PostgreSQL jako jedyne źródło prawdy

Jedna baza, wiele schematów: `core`, `fleet`, `rent`, `tms`, `fin`, `tax`, `assets`, `telematics`, `docs`, `integr`, `audit`.

**Dlaczego nie SQLite ani baza rozproszona typu D1:** zakres finansowo-księgowy wymaga transakcji obejmujących wiele tabel, widoków materializowanych, partycjonowania tabeli zdarzeń i realnego planera zapytań. To są wymagania twarde, nie preferencje.

**Dlaczego nie osobna hurtownia danych:** przy tej skali widoki materializowane wystarczą, a osobna hurtownia wprowadza drugie miejsce, w którym liczby mogą się rozjechać z pierwszym.

### 3. Wielonajemcowość w kolumnie, egzekwowana przez RLS

Każda tabela danych klienta ma `company_id`. **Izolację wymusza Row Level Security w PostgreSQL**, a nie dyscyplina programisty w każdym zapytaniu.

Aplikacja ustawia w transakcji `SET LOCAL app.company_ids` (spółki z jawnych nadań — odczyt) i `SET LOCAL app.company_id` (aktywna spółka — zapis), obie wyliczone z `core.user_company_access`, nigdy z parametru żądania. Polityki RLS porównują z nimi każdą operację; rola bazodanowa aplikacji **nie ma** uprawnienia `BYPASSRLS`. Szczegóły i granica zaufania: [projekt bazy](10-database-design.md), rozdział „Polityki RLS".

> **To jest wniosek z audytu działającego systemu, nie preferencja stylistyczna.** Tam izolacja opierała się na dopisywaniu warunku w każdym zapytaniu plus centralnym strażniku w routerze. Audyt znalazł **cztery podatności IDOR** na punktach pobierających pojedynczy rekord: lista była filtrowana, rekord nie.
>
> Znaleziono też przypadek, którego centralny strażnik **nie łapał z zasady**: usuwanie pozycji faktury po identyfikatorze ze ścieżki URL, z własną spółką w parametrze. Strażnik sprawdzał parametr, a atak go nie używał.
>
> Przy RLS ta klasa błędu nie powstaje, bo filtr jest w bazie, nie w zapytaniu.

### 4. Zdarzenie jako rekord pierwszej klasy

Tabela `fleet.events` jest partycjonowana miesięcznie i stanowi wspólną oś czasu pojazdu. Koszty, dokumenty i pozycje rejestrów **wskazują na zdarzenie**, nie duplikują jego danych.

Wynika z tego reguła obowiązująca w całym systemie: **kwota i wskaźnik istnieją w jednym miejscu**. Kilogramy CO2 liczy backend i zwraca użyty wskaźnik; front go tylko wyświetla.

> W systemie odniesienia dwie kopie tablicy wskaźników emisji rozjechały się nie tylko ze sobą, ale i z danymi. Eksport pokazywał kilogramy policzone jednym wskaźnikiem obok innego wskaźnika w nagłówku.

### 5. Integracje przez porty, z zapisem surowej odpowiedzi

Każda integracja zewnętrzna to moduł w `integr` z jednolitym kontraktem: pobranie → **zapis surowej odpowiedzi** → walidacja → mapowanie na zdarzenia.

Surowa odpowiedź zostaje. Bez niej po tygodniu nie da się odróżnić błędu dostawcy od błędu mapowania.

### 6. Kaskady pomocnicze muszą krzyczeć, nie schodzić po cichu

Tam, gdzie jest kilka źródeł danych o różnej jakości (OCR: kod Aztec → parser własny → model wizyjny), **powód zejścia na niższą warstwę trafia do odpowiedzi i do logu**.

> Powód jest konkretny: w systemie produkcyjnym wyczerpanie dziennego limitu usługi zewnętrznej objawiało się jako **gorsze dane**, a nie jako błąd. Dwie pełne rundy przetwarzania dały zero nowych odczytów i wyglądało to na sufit możliwości narzędzia, a nie na wyczerpany limit. Cicha kaskada kosztowała dwie diagnozy.

Metryka „procent dokumentów obsłużonych przez najniższą warstwę" jest w [monitoringu](08-cluster-deployment.md) alertem, nie ciekawostką.

### 7. Pola rozszerzalne w JSONB, nie w tabeli EAV

Kartoteka pojazdu ma kolumnę `extra JSONB` z indeksem GIN. Definicje pól (nazwa, typ, słownik) w osobnej tabeli per najemca.

**Dlaczego nie EAV** (tabela `atrybut / wartość`): zapytania z filtrowaniem po kilku atrybutach wymagają tylu złączeń, ile atrybutów. JSONB z GIN robi to jednym warunkiem.

**Dlaczego nie kolumny dodawane dynamicznie** przez `ALTER TABLE`: migracje przestają być odtwarzalne, a schemat różni się między najemcami.

## Stack

| Warstwa | Wybór | Uzasadnienie |
| --- | --- | --- |
| Frontend | TypeScript, React, Vite | dojrzałe, duży rynek pracy |
| Komputery | ten sam panel jako PWA (`vite-plugin-pwa`) | Windows, macOS, Linux bez osobnego kodu i instalatora |
| Mobile | React Native + Expo, SQLite na urządzeniu | iOS i Android z jednego kodu; offline, aparat, podpis; build i publikacja przez EAS |
| Tabele | TanStack Table + wirtualizacja | siatki na tysiące wierszy z konfiguracją kolumn w bazie |
| Stan serwera | TanStack Query | cache i unieważnianie bez własnego magazynu stanu |
| Backend | NestJS + OpenAPI | moduły odwzorowują granice domenowe; kontrakt generowany, nie pisany ręcznie |
| Zadania | BullMQ na Redisie | importy, ponowienia KSeF, przypomnienia, odświeżanie widoków |
| Baza | PostgreSQL 16 | RLS, partycjonowanie, widoki materializowane, JSONB |
| Pliki | S3/MinIO | skany dowodów, polisy, protokoły, załączniki |
| OCR | Python, FastAPI, RapidOCR | parser geometryczny; kontynuacja działającej usługi |
| Raporty | generowanie serwerowe do PDF/XLSX | bez plików szablonów na stacjach roboczych |
| Wdrożenie | Docker, Kubernetes, Helm, Argo CD | patrz [wdrożenie](08-cluster-deployment.md) |

## Kaskada OCR dokumentów

Kolejność warstw, od najpewniejszej:

| Warstwa | Pewność | Czas | Uwagi |
| --- | --- | --- | --- |
| **Kod Aztec z dowodu** | 100% | <1 s | dane z podpisanego ładunku, nie z rozpoznawania obrazu |
| **Parser geometryczny** | wysoka | 8–11 s | dopasowanie etykieta→wartość po współrzędnych |
| **Model wizyjny** | niska | zmienna | ostatnia deska ratunku, wymaga potwierdzenia przez człowieka |

**OCR nigdy nie jest na ścieżce synchronicznego żądania.** 8–11 sekund wyklucza odpowiedź na kliknięcie — przetwarzanie jest zadaniem w kolejce.

## Format zdarzenia

Zdarzenie floty w kontrakcie API i w `integr.outbox` (wiersz w `fleet.events` ma te same pola jako kolumny):

```json
{
  "id": 918273,
  "company_id": 3,
  "kind": "refuel",
  "occurred_at": "2026-10-08T06:42:00+02:00",
  "vehicle_id": 4411,
  "employee_id": 207,
  "amount_net": 412.36,
  "amount_gross": 507.20,
  "vat_amount": 94.84,
  "currency": "PLN",
  "document_id": 55012,
  "source": "fuel_import",
  "external_ref": "ORLEN-2026-10-000123456",
  "payload": {
    "card_number_last4": "4821",
    "volume_l": 71.4,
    "station_id": "PL-WAW-0213",
    "odometer_km": 184250
  }
}
```

Zasady kontraktu:

- `external_ref` + `source` + `company_id` to klucz deduplikacji — ten sam plik importu wczytany drugi raz nie tworzy nowych zdarzeń;
- kwoty jako liczby dziesiętne w JSON, w bazie `NUMERIC(14,2)`; nigdy typ zmiennoprzecinkowy w obliczeniach;
- `payload` trzyma dane specyficzne dla typu; pola, po których się filtruje lub liczy, mają własne kolumny, nie siedzą w `payload`;
- pojazd rozpoznany z numeru karty i przypisania karty w dniu transakcji, nigdy z numeru rejestracyjnego w pliku ([integracje](04-api-integrations.md)).

Zmiany propagowane między modułami idą przez `integr.outbox` w tej samej transakcji co zapis zdarzenia (wzorzec outbox), a worker BullMQ publikuje je dalej. Moduł nie odpytuje cudzych tabel.

## Środowiska

| Środowisko | Do czego | Dane |
| --- | --- | --- |
| `local` | praca programisty, Docker Compose | dane syntetyczne |
| `dev` | wspólne środowisko zespołu, każdy commit z gałęzi głównej | dane syntetyczne |
| `stage` | testy E2E, testy integracji z piaskownicami (KSeF test/demo) | dane syntetyczne albo zanonimizowana kopia |
| `demo` | demo dla potencjalnego klienta przed umową ([onboarding](14-onboarding-klienta.md)) | przykładowa flota albo lista pojazdów klienta bez danych osobowych; usuwane po 30 dniach |
| `prod` | własna flota i klienci zewnętrzni | produkcyjne |

Dane produkcyjne nie trafiają do `local` ani `dev`. Na fazy 0–1 wystarcza jeden serwer z Docker Compose ([zasoby](13-resources-and-prerequisites.md)); klaster to stan docelowy ([wdrożenie](08-cluster-deployment.md)).

## Co przenosimy z istniejącego systemu

Trzy elementy sprawdzone w produkcji, do przeniesienia bez przepisywania:

1. **Silnik podatkowy DT-1** — kategorie, progi, zwolnienia. Zgodność z bazą produkcyjną 0,24%, różnice wyjaśnione brakami danych wejściowych.
2. **Stawki gminne** — zweryfikowane 45/45 z uchwałą.
3. **Usługa OCR** — parser geometryczny z korekcją orientacji strony.

Czego **nie** przenosimy i dlaczego: [systemy odniesienia](12-source-systems.md), rozdział 4.

## Założenia do potwierdzenia

- **Zakres pracy offline aplikacji mobilnej** — technologia jest rozstrzygnięta (Expo, offline-first, kolejka zapisów z `client_uuid` i `Idempotency-Key`); otwarte jest, które ekrany poza protokołami i licznikiem muszą działać bez zasięgu.
- **Liczba równoczesnych użytkowników na najemcę** — wpływa na skalowanie warstwy API.
- **Lokalizacja danych** — jeśli wymagana Polska, wyklucza część dostawców chmury.
