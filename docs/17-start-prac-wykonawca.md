# Start prac — przekazanie dla wykonawcy

Dokument dla osoby, która zaczyna pisać kod FleetCore. Mówi, co jest gotowe, co zostało ustalone, od czego zacząć i czego jeszcze brakuje. Szczegóły są w pozostałych dokumentach — tutaj są odnośniki i kolejność.

Stan na 10.10.2026.

---

## 1. Co budujemy — w trzech zdaniach

FleetCore to system zarządzania flotą budowany od zera: kartoteka pojazdu, zdarzenia i koszty, podatek od środków transportowych (DT-1), rozliczenia, docelowo najem i transport. Zastępuje TaxOrder Pro, który ma błędy architektoniczne niedające się naprawić ewolucyjnie. Pierwszym klientem jest własna flota, kolejnymi — klienci zewnętrzni.

Najważniejsza zasada projektu: **zdarzenie floty zapisuje się raz** i wszystkie moduły (koszt, dekret, deklaracja, raport) korzystają z tego samego zapisu. Druga: **brak danych nigdy nie ma wartości domyślnej** — pole podatkowe bez wartości blokuje wyliczenie, zamiast je cicho zaniżać.

## 2. Decyzje już podjęte

| Decyzja | Gdzie opisana |
| --- | --- |
| Monorepo, modularny monolit NestJS, nie mikroserwisy | [architektura](03-architecture-and-stack.md) |
| PostgreSQL 16 jako jedyne źródło prawdy; izolacja najemców przez RLS w bazie | [projekt bazy](10-database-design.md) |
| Platformy: web + PWA (Windows, macOS, Linux), React Native/Expo (iOS, Android) | [brief](01-project-brief.md) |
| Produkt sprzedawany klientom zewnętrznym → wielonajemcowość i licencjonowanie modułów od początku | [brief](01-project-brief.md) |
| Integracja z ZSI na razie wyłącznie przez eksport plików | [platforma integracji](16-platforma-integracji.md) |
| Import/eksport, API publiczne, webhooki przez jeden wspólny rdzeń | [platforma integracji](16-platforma-integracji.md) |
| Przed umową z klientem — demo bez danych osobowych; audyt danych po umowie | [onboarding](14-onboarding-klienta.md) |
| Z TaxOrder Pro przenosimy wiedzę, testy i wybrane algorytmy — nie architekturę | [materiały TaxOrder](15-materialy-taxorder-pro.md) |

## 3. Decyzje jeszcze otwarte

Nie zgadujemy po cichu — przy każdej z nich zgłoś się do właściciela, zanim zaczniesz kod, który od niej zależy.

| Decyzja | Kto | Blokuje |
| --- | --- | --- |
| Lokalizacja danych: Polska czy UE; dostawca chmury | właściciel | wdrożenie poza lokalnym środowiskiem |
| Ostateczna nazwa produktu | właściciel | domena, bundle ID aplikacji mobilnej, sklepy |
| Zakres pracy offline aplikacji mobilnej poza protokołami i licznikiem | praktycy + zespół | fazę 3 |
| Pełna tabela kategorii DT-1 potwierdzona przez doradcę podatkowego | właściciel + doradca | fazę 2 |
| Format importu dekretów do ZSI | właściciel + księgowość | eksport do FK w fazie 2 |

## 4. Dostępy

| Co | Uprawnienie | Kiedy |
| --- | --- | --- |
| Repozytorium `adic94/fleetcore` | **Write** — tu powstaje kod | od razu |
| Repozytorium `adic94/taxorder-pro` | **Read** — push do `main` tego repozytorium to wdrożenie produkcyjne działającego systemu | od razu |
| Folder „FleetCore - backup i materiały" na Dysku Google | odczyt | **dopiero po podpisaniu umowy o poufności i umowy powierzenia danych** — zawiera dane kierowców i skany dowodów |
| Poświadczenia produkcyjne TaxOrder Pro (Cloudflare, Supabase, klucze API) | **brak** | nie są potrzebne do budowy FleetCore |

Do pracy nad kodem przed umową powierzenia wystarczą repozytoria i dane syntetyczne (`npm run db:seed`). Zanonimizowaną próbkę dowodów rejestracyjnych do testów OCR przygotuje właściciel.

## 5. Pierwszy dzień

### Uruchomienie

Wymagania: Node.js 22+, Docker Desktop, git. Instrukcja krok po kroku: [README](../README.md), „Pierwsze uruchomienie". W skrócie:

```bash
git clone https://github.com/adic94/fleetcore.git
cd fleetcore
cp .env.example .env
docker compose up -d postgres redis minio
npm install
npm run db:migrate
npm run db:seed
npm run test:gates
```

Wszystkie bramki muszą być zielone na czystym klonie. Jeśli nie są — to pierwszy błąd do zgłoszenia, nie do obejścia.

### Co przeczytać — w tej kolejności

1. [Brief](01-project-brief.md) — po co to powstaje, kryteria sukcesu, decyzje.
2. [Materiały z TaxOrder Pro](15-materialy-taxorder-pro.md) — co przejmujemy i gdzie to leży.
3. [Projekt bazy](10-database-design.md), rozdziały „Konwencje" i „Polityki RLS".
4. [Struktura repozytorium](09-repository-structure.md) — reguła granic modułów i bramki testowe.
5. [Roadmapa](07-roadmap.md) — fazy, kryteria ukończenia, kamienie milowe.

Resztę czyta się, gdy zaczyna się odpowiadający moduł; ścieżki w [indeksie](00-index.md).

## 6. Co jest gotowe, a czego nie ma

**Gotowe i sprawdzone** (szkielet fazy 0):

- schemat bazy: 13 migracji wykonanych na czystym PostgreSQL 16, RLS i uprawnienia dla każdej tabeli najemcy;
- bramka izolacji najemców: 11 testów, z kontrolą negatywną (po zepsuciu RLS testy upadają);
- zalążek silnika DT-1: dobór stawki z uchwały, 12 testów;
- API: `/v1/health`, `/v1/vehicles` z kontekstem spółki brany z nadań w bazie;
- panel React jako PWA, szkielety aplikacji mobilnej (Expo) i usługi OCR (FastAPI);
- CI: migracje dwukrotnie, izolacja, silnik DT-1, build.

**Nie ma jeszcze:** uwierzytelniania (w development użytkownika wskazuje nagłówek `X-Dev-User`), modułów domenowych poza odczytem pojazdów, importów, OCR, KSeF. Aplikacja mobilna nie była uruchamiana.

## 7. Faza 0 — zakres do zrobienia

Kryterium ukończenia z [roadmapy](07-roadmap.md): *administrator zakłada spółkę i użytkownika, użytkownik loguje się i wgrywa dokument, a próba sięgnięcia po dane innej spółki kończy się odmową — potwierdzoną testem automatycznym.*

Proponowana kolejność:

1. **Uwierzytelnianie**: logowanie hasłem, sesje, MFA obowiązkowe dla ról z dostępem do finansów; zastąpienie `X-Dev-User` w `TenantGuard`.
2. **Zakładanie najemcy** przez superadmina (spółka, moduły, pierwszy administrator) — bez późniejszego dostępu superadmina do danych.
3. **Administracja najemcy**: użytkownicy, role i nadania spółek (`core.user_company_access`), przełączanie aktywnej spółki.
4. **Ślad audytowy**: zapis do `audit.audit_logs` dla logowania, zmian uprawnień, eksportów, odmów dostępu.
5. **Dokumenty**: wgrywanie do magazynu obiektowego, deduplikacja po `sha256`, metadane w `docs.documents`.
6. **Reguła granic modułów** w linterze (import tylko przez `index.ts` modułu).
7. **Kontrakt OpenAPI** generowany z API i typy w `packages/contracts` generowane z niego.
8. **Zadanie cykliczne partycji** (`core.ensure_month_partitions`) w workerze.

Każdy nowy punkt API ma test w `tests/isolation/` w tym samym zgłoszeniu zmian.

## 8. Zasady pracy

- Praca na gałęziach i przez pull requesty; `main` zawsze zielony.
- Bramki uruchamiane lokalnie przed wysłaniem (`npm run test:gates`), nie tylko w CI.
- Migracji nie edytuje się po scaleniu — każda zmiana schematu to nowy plik.
- Test jest wiarygodny dopiero, gdy upada na kodzie sprzed naprawy.
- Żadnych danych produkcyjnych ani osobowych w repozytorium — także w testach i zrzutach ekranu.
- Rozbieżność między dokumentacją a kodem zgłaszamy i poprawiamy dokumentację w tym samym PR. Dokumentacja w `docs/` jest projektem; migracje i kod są źródłem prawdy.

## 9. Pytania do wykonawcy na start

Odpowiedzi pomogą ustalić harmonogram:

1. Czy szacunek 2–3 osobomiesięcy na fazę 0 i 8–12 na fazę 1 ([brief](01-project-brief.md)) jest realny przy Twoim składzie zespołu?
2. Kto poza Tobą pracuje nad projektem i w jakim wymiarze?
3. Czy widzisz w architekturze lub stosie coś, co chcesz zmienić, zanim powstanie więcej kodu? Teraz zmiana jest najtańsza.
4. Jaki rytm spotkań i raportowania postępów proponujesz?
