# Struktura repozytorium i modułów

## Monorepo

Jedno repozytorium, wspólne typy między frontendem a backendem. Przy zespole tej wielkości koszt synchronizacji dwóch repozytoriów przewyższa korzyść z ich rozdzielenia.

```
fleetcore/
├── apps/
│   ├── api/                  # NestJS — backend
│   ├── web/                  # React — panel
│   ├── mobile/               # React Native + Expo — iOS i Android
│   └── ocr/                  # Python/FastAPI — OCR dokumentów
├── packages/
│   ├── contracts/            # typy wspólne, generowane z OpenAPI
│   ├── tax-engine/           # silnik DT-1 (przeniesiony)
│   ├── rates/                # stawki gminne
│   └── ui/                   # komponenty wspólne
├── db/
│   ├── migrations/           # migracje, numerowane
│   ├── policies/             # polityki RLS
│   └── seeds/                # słowniki startowe
├── deploy/
│   ├── helm/
│   └── argocd/
├── tests/
│   ├── unit/                 # bramki bez sieci
│   ├── e2e/
│   └── isolation/            # testy izolacji najemców
├── tools/                    # narzędzia diagnostyczne i migracyjne, nie idą na produkcję
└── docs/
```

## Moduły backendu

```
apps/api/src/modules/
├── core/         # najemcy, użytkownicy, uprawnienia, słowniki
├── fleet/        # pojazdy, zdarzenia, rejestry
├── rent/         # cenniki, rezerwacje, najem
├── tms/          # zlecenia transportowe drogowe, dokumentacja przewozowa
├── fin/          # koszty, dekretacja, rejestry VAT, KSeF
├── tax/          # DT-1, opłata środowiskowa, CO2
├── assets/       # wyposażenie, telefony, protokoły sprzętu, oświadczenia
├── telematics/   # GPS, przebiegi, jazdy prywatne
├── docs/         # dokumenty, OCR, magazyn plików
└── integr/       # klienci integracji zewnętrznych
```

## Reguła granic

Moduł sięga do innego **wyłącznie** przez jego interfejs publiczny albo przez zdarzenie. Nigdy przez cudzą tabelę.

Wymuszane mechanicznie, nie umową:

- każdy moduł ma plik `index.ts` z jawnym eksportem — reszta jest prywatna;
- reguła lintera blokuje import po ścieżce głębszej niż katalog modułu;
- każdy schemat bazy ma dedykowaną rolę; moduł nie dostaje uprawnień do cudzych tabel.

Trzeci punkt jest najważniejszy, bo jako jedyny działa też wtedy, gdy ktoś obejdzie lintera.

## Własność

| Obszar | Właściciel | Konsultuje |
| --- | --- | --- |
| `core`, `db/policies` | architekt | wszyscy |
| `fleet`, `assets` | zespół floty | fleet manager |
| `rent` | zespół floty | dział najmu |
| `tms` | zespół transportu | **dyspozytor (obowiązkowo)** |
| `fin`, `tax` | zespół finansów | księgowość, doradca podatkowy |
| `integr` | zespół platformy | właściciel danej integracji |
| `ocr` | zespół platformy | zespół floty |

## Konwencje

- Kod, nazwy zmiennych i funkcji: **angielski**. Interfejs użytkownika: **polski**, przez warstwę tłumaczeń.
- Nazwy kolumn w bazie: angielski. Wyjątek: pola odwzorowujące rubryki dokumentów urzędowych zachowują oznaczenie rubryki w komentarzu.
- Każdy nowy punkt API ma wpis w testach izolacji **w tym samym zgłoszeniu zmian**.
- Migracje: numerowane, nigdy modyfikowane po scaleniu. Zmiany strukturalne (usunięcie, przemianowanie) w osobnej konwencji nazw, żeby nie trafiły do automatu uruchamiającego migracje przyrostowe.

## Bramki testowe

W `tests/unit/` mieszkają testy bez sieci i bez zależności zewnętrznych — mają działać w dwadzieścia sekund i chronić przed konkretnymi, zdarzonymi już klasami błędów:

| Bramka | Czego pilnuje | Skąd się wzięła |
| --- | --- | --- |
| `tenant-isolation` | każdy punkt API odmawia dostępu między najemcami | 4 podatności IDOR w audycie |
| `tax-rates` | stawki zgodne z uchwałą co do złotówki | 45/45 zweryfikowanych pozycji |
| `co2-factors` | jedna tablica wskaźników, dopasowanie po fragmencie | dwie rozjechane kopie |
| `migration-apply` | migracje przechodzą na czystej bazie i przy powtórzeniu | pliki padające przy każdym powtórzeniu |
| `schema-diff` | stan bazy zgodny z repozytorium | dryf schematu wykryty po fakcie |
| `report-columns` | kolumny raportów istnieją w schemacie | raporty zwracające pustą tabelę bez błędu |
| `ocr-sanitize` | identyfikator modelu i opis pola nie trafiają jako wartość | 8% rekordów z wyciekiem |
| `cdn-sri` | skrypty zewnętrzne mają sumę kontrolną | brak weryfikacji integralności |

## Reguła wiarygodności testu

**Test uznaje się za wiarygodny dopiero, gdy upadnie na kodzie sprzed naprawy.**

To nie jest formalność. Przykłady z systemu odniesienia:

- Bramka szukała literału wyrażeniem regularnym, a przy nietrafieniu wypisywała „pomijam" — czyli przestawała mierzyć cokolwiek i świeciła na zielono. Brak mierzonej stałej musi być **porażką**, nie pominięciem.
- Test wyciągający zapytania wyrażeniem regularnym przechodził przez granice literałów i padał **tak samo** na kodzie starym i nowym. Wykryła to dopiero kontrola negatywna.
- Test czekał na selektor, który spełniały szkielety ładowania wbudowane w stronę — warunek był spełniony, zanim dane w ogóle przyszły.

Stąd zasada uzupełniająca: **lista znanych wyjątków w bramce jest tymczasowa i ma zostać wyzerowana.** Wpis na takiej liście oznacza dług, nie zwolnienie z reguły. Dopisanie tam pozycji „żeby uciszyć test" jest zabronione i opatrzone komentarzem w kodzie.

## Narzędzia

`tools/` — narzędzia diagnostyczne i migracyjne, nie wchodzą na produkcję. Każde ma wpis w `tools/README.md`. Narzędzia jednorazowe trafiają do archiwum, nie zostają w katalogu głównym.

Narzędzie zapisujące dane osobowe (VIN-y, numery rejestracyjne, dane właścicieli) **odmawia zapisu do drzewa repozytorium**. Nie ostrzega — odmawia.
