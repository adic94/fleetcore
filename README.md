# FleetCore

System zarządzania flotą: kartoteka pojazdu, zdarzenia i koszty, podatek od środków transportowych (DT-1), rozliczenia, najem, transport, aplikacja mobilna. Budowany od zera, dla własnej floty i klientów zewnętrznych.

> **Nazwa robocza.** „FleetCore" do podmiany przed pierwszą publikacją (domena, App Store, Google Play, bundle ID w `apps/mobile/app.json`).

**Zaczynasz pracę: [docs/17-start-prac-wykonawca.md](docs/17-start-prac-wykonawca.md).** Cała dokumentacja: [docs/00-index.md](docs/00-index.md).

Ten plik opisuje tylko, jak uruchomić kod.

## Stan

Szkielet fazy 0 ([roadmapa](docs/07-roadmap.md)). Działa i jest sprawdzone:

| Element | Stan |
| --- | --- |
| Schemat bazy (`db/migrations/`) | 13 migracji z projektu bazy, wykonane na czystym PostgreSQL 16 |
| RLS dla każdej tabeli z `company_id` | wygenerowane w `0100_rls_and_grants.sql` |
| Test izolacji najemców (`tests/isolation/`) | 11 testów; kontrola negatywna: po zepsuciu RLS testy upadają |
| Silnik DT-1 — dobór stawki (`packages/tax-engine/`) | zalążek z 12 testami, w tym na błąd z TaxOrder Pro (brak osi → „2") |
| API (`apps/api/`, NestJS) | `/v1/health`, `/v1/vehicles`; kontekst spółki z nadań w bazie |
| Panel (`apps/web/`, React + Vite + PWA) | ekran startowy, instalowalny jako aplikacja na Windows/macOS/Linux |
| Aplikacja mobilna (`apps/mobile/`, Expo) | szkielet; **zależności nie są zainstalowane w tym repozytorium** — patrz niżej |
| OCR (`apps/ocr/`, FastAPI) | szkielet z Dockerfile; kaskada do przeniesienia z TaxOrder Pro |
| CI (`.github/workflows/ci.yml`) | migracje ×2, izolacja, silnik DT-1, build |

Nie ma jeszcze: uwierzytelniania (w development użytkownika wskazuje nagłówek `X-Dev-User`), modułów domenowych poza odczytem pojazdów, importów, OCR, KSeF.

## Wymagania

- Node.js 22+ (sprawdzone na 24)
- Docker Desktop
- Python 3.12+ (tylko dla `apps/ocr` poza Dockerem)

## Pierwsze uruchomienie

```bash
cp .env.example .env
docker compose up -d postgres redis minio
npm install
npm run db:migrate
docker compose exec postgres psql -U postgres -d fleetcore -c "ALTER ROLE fleetcore_app PASSWORD 'apptest'"
npm run db:seed
npm run test:gates
```

API i panel (w dwóch terminalach):

```bash
npm run dev:api
npm run dev:web
```

Panel: http://localhost:5173. API: http://localhost:3000/v1/health. Odczyt pojazdów wymaga nagłówka `X-Dev-User` z identyfikatorem wypisanym przez `db:seed`.

### Aplikacja mobilna

`apps/mobile` jest **poza** workspace'ami npm — Expo pracuje pewniej z własnym `node_modules`.

```bash
cd apps/mobile
npm install
npx expo start
```

## Zasady, które obowiązują od pierwszej linii kodu

Pełna lista: [docs/09-repository-structure.md](docs/09-repository-structure.md). Najważniejsze:

1. **Izolacja najemców robi baza (RLS), nie kod.** Zapytania nie mają `WHERE company_id = …`; kontekst ustawia wyłącznie `DbService.withTenant`. Spółka pochodzi z nadań w `core.user_company_access`, nigdy z parametru żądania.
2. **Każdy nowy punkt API ma test w `tests/isolation/`** w tym samym zgłoszeniu zmian.
3. **Brak danych to `NULL`, nie `0`** i nie wartość domyślna. Pole podatkowe bez wartości blokuje wyliczenie, zamiast je cicho zaniżać.
4. **Migracji nie edytuje się po scaleniu** — narzędzie `tools/migrate.mjs` zatrzyma się na zmienionym pliku. Pliki wycofujące (`rollback`, `down`) w `db/migrations` są błędem.
5. **Uprawnienia w bazie nadaje się tabela po tabeli**, nigdy `GRANT … ON ALL TABLES IN SCHEMA` — to otwiera aplikacji widoki materializowane.
6. **Test jest wiarygodny dopiero, gdy upada na kodzie sprzed naprawy.**
7. **Żadnych danych produkcyjnych ani osobowych w repozytorium** — `.gitignore` blokuje typowe formaty, ale to tylko ostatnia linia obrony.

## Struktura

```
apps/
  api/         NestJS — backend, kontekst najemcy, moduły domenowe
  web/         React + Vite + PWA — panel (przeglądarka, Windows, macOS, Linux)
  mobile/      React Native + Expo — iOS, Android
  ocr/         Python + FastAPI — OCR dokumentów
packages/
  contracts/   typy wspólne (docelowo generowane z OpenAPI)
  tax-engine/  silnik DT-1
db/migrations/ migracje SQL, numerowane
tests/isolation/ bramka izolacji najemców
tools/         migracje, dane syntetyczne, narzędzia
docs/          dokumentacja projektu
```
