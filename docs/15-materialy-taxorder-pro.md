# Materiały z TaxOrder Pro — co dostaje zespół FleetCore

FleetCore powstaje od nowa, bo TaxOrder Pro ma błędy architektoniczne, których nie da się naprawić ewolucyjnie ([systemy odniesienia](12-source-systems.md), rozdział 4). TaxOrder Pro jest jednocześnie **najcenniejszym źródłem wiedzy** w projekcie: działał produkcyjnie na realnej flocie i każdy jego błąd jest zmierzony i opisany. Ten dokument mówi, gdzie co leży, co czytać najpierw i czego nie kopiować.

## Zasada

**Z TaxOrder Pro przenosimy wiedzę, testy i wybrane algorytmy — nie architekturę ani kod aplikacji.** Każdy przenoszony fragment przechodzi przez bramki testowe FleetCore i przegląd; „działało w TaxOrder" nie jest dowodem poprawności (patrz silnik DT-1 i brakujący wymiar zawieszenia w tabeli stawek).

---

## 1. Repozytorium kodu

| | |
| --- | --- |
| Adres | `github.com/adic94/taxorder-pro` (prywatne) |
| Gałąź produkcyjna | `main` — **push do `main` wdraża produkcję** (Cloudflare Pages + Worker) |
| Kopie robocze | komputer HP (`CodeGPT\gpu-diagnostics\taxorder-pro`) i MT0268 (`Desktop\Program flotowy\taxorder-pro`), synchronizowane przez git (`tools/sync.js`) |
| Rozmiar | ok. 630 plików bez zależności |

### Dostęp dla zespołu FleetCore

- **Uprawnienie „Read" na GitHubie, nie „Write".** Zapis do `main` to wdrożenie produkcyjne działającego systemu podatkowego — zespół nowego systemu nie potrzebuje tej możliwości i nie powinien jej mieć.
- **Bez poświadczeń produkcyjnych** (Cloudflare, Supabase, klucze API `tord_live_…`, `.env`). Plik `.env` nie jest w repozytorium i tak ma zostać.
- Przed nadaniem dostępu: **wszystkie gałęzie robocze wypchnięte na GitHuba**. Stan na 10.10.2026: gałąź `backup/uncommitted-ops-center-2026-09-24` z trzema commitami (centrum operacyjne A–F, eksport DR do XLSX, bezpieczny import DR, offline OCR) istnieje **wyłącznie lokalnie na komputerze HP**. Wypchnięcie gałęzi innej niż `main` nie wdraża produkcji.

### Co czytać najpierw — w tej kolejności

| Plik | Dlaczego |
| --- | --- |
| `CLAUDE.md` (ok. 175 KB) | **dziennik zmierzonych pułapek** — źródło większości ostrzeżeń w tej dokumentacji; czytać rozdziałami według potrzeby, nie od deski do deski |
| `CODEBASE_MAP.md` | mapa endpointów, modułów i tabel D1 |
| `docs/decisions/ADR-001…014` | decyzje architektoniczne; ADR-004 (DMC i `??`), ADR-014 (granica z ERP) przechodzą do FleetCore niemal wprost |
| `docs/audits/`, `docs/AUDYT_2026-07-26.md` | audyty bezpieczeństwa i warstw — w tym 4 podatności IDOR, z których wynika RLS we FleetCore |
| `docs/MOST-DWA-KOMPUTERY.md` | jak działa praca na dwóch komputerach i dlaczego push do `main` jest wdrożeniem |
| `docs/BENCHMARK_PASCOM_I_RYNEK_2026-08-31.md` | porównanie z PasCom i rynkiem |

### Co przenosimy (do przeglądu i przepisania na TypeScript/NestJS tam, gdzie trzeba)

| Element | Gdzie w repozytorium | Uwaga przy przenoszeniu |
| --- | --- | --- |
| Silnik DT-1 | `tools/dt1-wyliczenie.js`, logika kategorii w `app.js` (`getCat()`) | **uzupełnić o wymiar zawieszenia i podstawę masy** ([opis produktu](02-product-functional-spec.md)); testy na danych produkcyjnych przed i po |
| Scalanie źródeł z rangami | `tools/flota-master.js` | rangi przenieść do konfiguracji najemcy (`core.source_ranks`) |
| Usługa OCR dowodów | `ocr-service/` (Python, FastAPI) | korekcja orientacji strony, bramki sanityzacji wyniku |
| Dekodowanie kodu Aztec | `modules/aztec-*.js`, `tools/aztec-*.js` | ścieżka 17/17 pól sprawdzona end-to-end |
| Importy | `tools/xlsx-import.js`, `modules/csv-import.js`, `modules/bulk-import.js` | MyCar = TSV w UTF-16LE mimo rozszerzenia `.xls` |
| Most ZSI | `tools/zsia-sync.ps1` | wzorzec odczytu pojazdów i kierowców z ZSI; decyzja o sposobie integracji otwarta ([systemy odniesienia](12-source-systems.md), rozdział 5) |
| Bramki testowe | `tests/unit/` (ok. 40 plików) | przenoszone jako **scenariusze**; każda musi upaść na kodzie sprzed naprawy |
| Narzędzia diagnostyczne | `tools/dr-ocr-boxes.js`, `tools/dr-validate-ocr.js`, `tools/cepik-probe.js` | do `tools/` FleetCore, nie na produkcję |

### Czego nie przenosimy

Pełna lista z uzasadnieniem: [systemy odniesienia](12-source-systems.md), rozdział 4. W skrócie: integracja KSeF (API, którego już nie ma), pobieranie z otwartego API CEPiK po numerze rejestracyjnym (martwy filtr), baza D1/SQLite, frontend bez frameworka (`app.js` ok. 600 KB, `index.html` ok. 370 KB), migracje `schema_v*.sql` razem z plikami `_ROLLBACK` (przyczyna nocnego kasowania tabel).

---

## 2. Dane i dokumenty poza repozytorium

| Materiał | Gdzie | Zawiera dane osobowe |
| --- | --- | --- |
| Kopie zapasowe i raporty TaxOrder | `Documents\taxorder-backupy` (komputer HP): checklisty braków DT-1, wyniki OCR dowodów, raporty dla zarządu | **tak** — numery rejestracyjne, VIN, w części nazwiska |
| Skany dowodów rejestracyjnych | `Documents\taxorder-dr-pdf-batch` (komputer HP), ok. 1270 plików PDF | **tak** — dane posiadaczy i właścicieli |
| Analiza ZSI i pliki źródłowe | komputer **MT0268**, m.in. `Desktop\Dokumentacja pojazdów\Pulpit\Brak VIN w ZSI.xlsx` | **tak** — kierowcy |
| Eksport MyCar, lista kart ORLEN | `Downloads` (komputer HP) | tak — przypisania kart do osób |
| Szablony importu Softry | `Desktop\SOFTRA\!IMPORT` (komputer HP) | szablony nie; wypełnione eksporty tak |
| Archiwum korespondencji | `Desktop\Dysk przenośny\mToilet\…\Archiwum_Poczta` | tak — **nie przekazywać**, poza zakresem projektu |

**Przekazanie danych z danymi osobowymi wymaga umowy powierzenia (albo podpowierzenia) z wykonawcą** — to dane pracowników i kontrahentów spółek, których administratorem nie jest zespół FleetCore. Do pracy na kodzie wystarczają:

- repozytorium (bez danych produkcyjnych),
- **zanonimizowana próbka**: kilkanaście skanów dowodów z zaczernionymi danymi posiadacza do testów OCR, lista pojazdów bez nazwisk do testów silnika DT-1,
- pełne dane dopiero na etapie migracji własnej floty (faza 1), pod umową.

---

## 3. Lista kontrolna przekazania

Po stronie właściciela projektu:

- [ ] Wypchnąć na GitHuba wszystkie lokalne gałęzie TaxOrder Pro z komputera HP **i z MT0268**.
- [ ] Nadać Rafałowi dostęp **Read** do `adic94/taxorder-pro` (GitHub → Settings → Collaborators → Add people → rola Read).
- [ ] Skopiować z MT0268 materiały analizy ZSI do wspólnego, kontrolowanego miejsca.
- [ ] Podpisać z wykonawcą umowę o poufności i umowę powierzenia danych — **przed** przekazaniem czegokolwiek z sekcji 2.
- [ ] Przygotować zanonimizowaną próbkę danych testowych.
- [ ] Ustalić z administratorem ZSI sposób integracji (eksport/API vs widoki tylko do odczytu).

Po stronie wykonawcy:

- [ ] Przeczytać `CLAUDE.md` TaxOrder Pro w części dotyczącej silnika DT-1, OCR i scalania źródeł, zanim powstanie odpowiadający moduł FleetCore.
- [ ] Dla każdego przenoszonego elementu z tabeli w sekcji 1 — test, który upada na kodzie TaxOrder Pro tam, gdzie TaxOrder Pro ma znany błąd.
