# Integracje API

Każda integracja ma ten sam kształt: pobranie → **zapis surowej odpowiedzi** → walidacja → mapowanie na zdarzenia.

> **Ten dokument przeczytaj w całości przed pierwszym wywołaniem jakiegokolwiek API.** Zawiera pułapki zmierzone na rzeczywistych integracjach, z których każda dawała poprawnie wyglądające dane zamiast błędu.

## Reguła nadrzędna: odpowiedź nie dowodzi, że filtr zadziałał

API, które nie zna parametru, zwykle go **ignoruje**, zamiast odrzucić. Odpowiedź wygląda wtedy jak trafienie: HTTP 200, komplet pól, poprawne typy, sensowne wartości.

**Każdy klient integracji ma obowiązkowy test kontrolny przed przebiegiem masowym:** to samo zapytanie z **inną wartością filtra**. Identyczny rekord oznacza martwy filtr i przebieg się nie rozpoczyna.

To nie jest teoria. Zapytanie do publicznego rejestru pojazdów o numer `WZ003EY` zwróciło Toyotę Corollę zarejestrowaną 2026-01-02, podczas gdy pod tym numerem jeździ Mercedes Sprinter z przebiegiem 230 998 km. Powtórzone dla innych numerów i innych okien dat — za każdym razem pierwszy rekord z zakresu. 68 pól, zero błędów, dane całkowicie nie te.

Przebieg na całej flocie przypisałby cudze dane do kilkuset pojazdów — **bez możliwości wykrycia po fakcie**.

Wariant testu do wyboru:
- ten sam zakres, **inna wartość filtra** → identyczny rekord = filtr martwy;
- zapytanie **bez filtra** → jeśli zwraca to samo, filtr nic nie zawężał.

Dopiero **różne rekordy dla różnych wartości** dowodzą, że parametr działa.

---

## KSeF — Krajowy System e-Faktur

| Parametr | Wartość |
| --- | --- |
| Środowiska | `api.ksef.mf.gov.pl/v2`, `api-demo.ksef.mf.gov.pl/v2`, `api-test.ksef.mf.gov.pl/v2` |
| Źródło kontraktu | `open-api.json` z repozytorium Ministerstwa Finansów (78 ścieżek) |
| Uwierzytelnianie | `/auth/challenge` → token KSeF (szyfrowany) **albo** podpis XAdES → `/auth/token/redeem` |
| Sesja | `/sessions/online`, wymaga `formCode` i parametrów szyfrowania |
| Format faktury | **FA(3)** |

> **Pułapka adresowa.** Hosty `ksef.mf.gov.pl` i `ksef-test.mf.gov.pl` zwracają `text/html` — to strony **portalu**, nie API. Ścieżki w stylu `/api/common/Online/Session/AuthorisationChallenge` pochodzą z **KSeF 1.0** i zrywają połączenie bez odpowiedzi.
>
> Druga pułapka: dokumentacja podaje adresy z `/docs/v2` (Swagger), a sekcja `servers` w samym `open-api.json` — **`/v2` bez `/docs`**. To drugie jest bazą dla wywołań.

**Kontrakt bierzemy wyłącznie z `open-api.json`.** Nie z dokumentacji opisowej i nie z klientów w innych językach — Ministerstwo nie wydaje klienta JS/TS; istnieją oficjalne klienty C# i Java.

### Kolejka offline — wymaganie projektowe

Nieudana wysyłka trafia do kolejki z ponawianiem. **Kolejka musi mieć monitoring i limit**, bo przy martwym punkcie końcowym rośnie w nieskończoność: ponawianie do 10 razy na fakturę, każda próba w pustkę.

Alert: kolejka > 50 pozycji albo najstarsza > 24 h.

---

## CEPiK / CEP — dane z rejestru pojazdów

Dwa różne kanały, których nie wolno mylić.

### Otwarte dane — do uzupełniania pojedynczych pól, nie do przebiegów masowych

- Publiczny, bez nagłówka autoryzacji. Limit niski, 429 przychodzi szybko — **odstęp 900 ms po każdym żądaniu, także nieudanym**.
- Okno dat ma twardy limit **dwóch lat kalendarzowych**. Serwer odrzuca szersze zapytanie błędem 400 z komunikatem wprost. Zapytanie o 30 lat naraz nie zwraca „braku pojazdów" — zwraca odrzucenie.
- **Filtr po numerze rejestracyjnym nie działa** (patrz reguła nadrzędna wyżej). Do czasu rozstrzygnięcia: żadnych przebiegów masowych.
- **Pole VIN nie istnieje w odpowiedzi** — sprawdzone na pełnej liście ~70 pól. Parametr `vin=` przyjmuje wartość, ale wyniku nie da się zweryfikować, bo API nigdy nie zwraca VIN-u.
- Wartościowe są `liczba-osi` i `rodzaj-zawieszenia` — akurat te pola, których brakuje najbardziej, bo od 12 t decydują o stawce podatku.

### Teletransmisja CEP — właściwa droga docelowa

Oficjalny dostęp z poświadczeniami, zamiast zepsutego punktu otwartych danych. **Wymaga wniosku o długim czasie realizacji** — złożyć jak najwcześniej, niezależnie od fazy projektu.

---

## Karty paliwowe

Import plików (CSV, XLS) albo API, zależnie od dostawcy. Schematy importu **definiowane przez użytkownika**, bo każdy dostawca ma inny układ kolumn.

**Rozpoznanie pojazdu: numer karty → przypisanie karty w okresie transakcji.** Nigdy po numerze rejestracyjnym z pliku — numer w pliku bywa przestarzały albo błędnie wpisany przez stację.

Z tego wynika wymaganie w bazie: przypisanie karty do pojazdu ma **zakres dat** i ograniczenie wykluczające nakładanie się okresów. Bez tego import nie ma jak rozstrzygnąć, czyj był koszt.

**Deduplikacja importu.** Każda pozycja ma identyfikator u źródła; indeks unikalny po `(najemca, źródło, identyfikator)` blokuje powtórne wczytanie tego samego pliku — najczęstszy błąd obsługi.

### Weryfikacja krzyżowa z telematyką

Tankowanie bez pojazdu w promieniu geofencu stacji w oknie ±15 minut trafia na listę do wyjaśnienia. To jeden z niewielu mechanizmów, który **wykrywa nadużycie kartą**, a nie tylko je rejestruje.

---

## Telematyka GPS

Pułapki zmierzone na rzeczywistym API dostawcy — warte sprawdzenia u każdego, bo są typowe:

- Punkty końcowe potrafią używać **niespójnych nazw pól** (`VehicalID` w jednym, `VehicleId` w drugim — literówka utrwalona w API). Złe pole = **pusty wynik bez błędu**.
- Odpowiedzi mają **HTTP 200 także przy błędzie** — o powodzeniu decyduje pole `ErrorCode`, nie status HTTP.
- Identyfikator parametru (np. poziomu paliwa) bywa **per pojazd**. Nie hardkodować.
- Podsumowania zwracane jako `HH:MM:SS` **gubią doby powyżej 24 h**. Do sum używać wartości w sekundach.
- Współrzędne o wartości granicznej (np. `361`) oznaczają **wyłączony moduł GPS**, nie ostatnią znaną pozycję.
- Limit ~3–5 żądań/s. Do ciągłego zasysania — strumień, nie REST w pętli.

**Wymaganie do zgłoszenia dostawcy: czas pracy z obrotów silnika, nie z zapłonu.** Dla pojazdów pracujących na postoju z napędem pomocniczym zapłon nie opisuje pracy.

---

## ERP klienta — u nas ZSI

Dwukierunkowo: z ERP pojazdy, kierowcy i dane uzupełniające (norma EURO, przebiegi); do ERP dekrety i dokumenty kosztowe do zaksięgowania. **Na razie wyłącznie przez eksport plików** (decyzja z 10.10.2026), API ZSI później. Szczegóły: [systemy odniesienia](12-source-systems.md), rozdział 5, i [platforma integracji](16-platforma-integracji.md).

Zasady dla każdego ERP, nie tylko ZSI:

- **zapis do bazy ERP — nigdy**; wyłącznie przez mechanizm importu albo API dostawcy ERP;
- dokument wysłany do ERP ma wersję i sumę kontrolną; ta sama wersja nie wychodzi dwa razy;
- brak potwierdzenia z ERP to stan `exported`, nie `posted` — status „zaksięgowano" wymaga uzgodnienia zwrotnego.

---

## e-TOLL i opłaty drogowe

Import zestawień przejazdów, dopasowanie do pojazdu i do kursu transportowego.

Rozliczenie kursu bez opłat drogowych nie jest rozliczeniem — to pozycja kosztowa porównywalna z paliwem.

---

## Ubezpieczyciele

**Brak jednolitego API na rynku.** Realistycznie: import polis z plików, OCR dokumentu polisy, ręczne uzupełnienie.

Projektujemy pod import i **zakładamy brak integracji online** — inaczej moduł polis zablokuje się na oczekiwaniu na coś, czego nie będzie.

---

## Banki

Import wyciągów w formacie **MT940 lub CSV**, dopasowanie wpłat do należności najmu. Generowanie plików przelewów do banku.

Kierunek jednostronny: czytamy wyciągi i generujemy pliki, **nie zlecamy przelewów przez API**.

---

## OCR dokumentów

### Kaskada

1. **Kod Aztec z dowodu rejestracyjnego** — pewność 100%, dane z podpisanego ładunku.
2. **Parser geometryczny** — dopasowanie etykieta→wartość po współrzędnych bounding boxów.
3. **Model wizyjny** — ostatnia warstwa, wymaga potwierdzenia przez człowieka.

### Pułapka, która daje ciche przekłamanie zamiast pustego pola

> **Orientacja strony.** Dowód rejestracyjny jest fizycznie poziomy. Przy renderze pionowym klasyfikator prostuje czytelność **każdej linii z osobna**, więc tekst wygląda poprawnie — ale **układ pozostaje obrócony**: etykieta ląduje po prawej od swojej wartości. Parser, szukając wartości po prawej, bierze **sąsiednią rubrykę**.
>
> Zmierzony efekt: `DMC = 1882` — to odczyt z „18,82 kN", czyli z **nacisku osi**. Prawdziwa DMC: 3210 kg. Wartość mieści się w dopuszczalnym zakresie, wygląda wiarygodnie i **trafiłaby do deklaracji podatkowej bez żadnego sygnału**.
>
> Dodatkowo: kierunek obrotu nie jest oczywisty. Przy złym kierunku tekst nadal jest czytelny, a układ wychodzi lustrzany — objaw identyczny jak przed poprawką.

**Zabezpieczenie ogólne: świadomość jednostek.** Zakres odpowiada na pytanie „czy liczba jest sensowna", jednostka na „czy to w ogóle ta wielkość". Przy sąsiadujących rubrykach drugie pytanie jest ważniejsze — samo `1882` przechodzi każdy zakres. **Pole z jednostką inną niż oczekiwana jest odrzucane**; brak jednostki pozostaje dopuszczalny.

### Druga klasa błędów: wyciek własnej infrastruktury do danych

Dwa zmierzone przypadki:

1. **Identyfikator modelu jako wartość pola pojazdu** — 8% rekordów w jednym przebiegu. Pojazd dostał markę równą nazwie modelu AI. To nie halucynacja, tylko wyciek koperty odpowiedzi do pól: `{...odpowiedź}` zamiast `{...odpowiedź.pola}`.
2. **Opis pola przepisany jako wartość** — model dostaje w instrukcji opis „D.3 — model, np. ACTROS lub SPRINTER" i zwraca go dosłownie jako wartość.

Obie bramki stoją w **jednym miejscu** — funkcji czyszczącej wynik, przez którą przechodzą wszystkie warstwy kaskady.

> **Nie uogólniać reguły 2 na „wartość zawiera się w opisie".** Kusi, bo brzmi szerzej. Opisy pól **z założenia wymieniają poprawne odpowiedzi**: opis pola „zawieszenie" podaje „pneumatyczne", opis „przeznaczenie" podaje „SAMOCHÓD CIĘŻAROWY". Zmierzone: taka wersja kasowała sześć poprawnych odczytów. Dopasowanie **od początku wartości** tej wady nie ma.

### Trzecia: kody rubryk i strefy techniczne dokumentu

Parser potrafi wziąć za wartość:
- **kod rubryki** (`marka = "D.3"`, `nrHomolog = "L"`),
- **strefę MRZ** dokumentu jako numer homologacji — wygląda urzędowo, bo nim jest, tylko to inny fragment dokumentu.

Bramka na kody rubryk **musi mieć wyjątek dla pola „rodzaj paliwa"** — tam „D", „B", „G" to poprawne wartości.

---

## Uwierzytelnianie i SSO

Docelowo OIDC (Microsoft Entra ID, Google Workspace). Na start logowanie lokalne z hasłem i **drugim składnikiem obowiązkowym dla ról z dostępem do finansów**.

---

## Wewnętrzne API FleetCore

REST, kontrakt OpenAPI generowany z kodu NestJS; typy dla frontendu i aplikacji mobilnej generowane z kontraktu (`packages/contracts`). Spółka, w kontekście której działa żądanie, pochodzi z sesji i z `core.user_company_access` — **nigdy z parametru w ścieżce czy w treści żądania**. Każdy punkt poniżej ma wpis w teście izolacji najemców.

Zasób startowy (fazy 0–2):

```http
GET    /v1/health
POST   /v1/auth/login
POST   /v1/auth/mfa/verify
GET    /v1/me/companies                      # spółki z jawnych nadań
POST   /v1/me/active-company                 # przełączenie kontekstu spółki

GET    /v1/vehicles                          # siatka z filtrami i polami rozszerzalnymi
POST   /v1/vehicles
GET    /v1/vehicles/{id}
PATCH  /v1/vehicles/{id}                     # pola podatkowe wymagają document_id
GET    /v1/vehicles/{id}/events
GET    /v1/vehicles/{id}/provenance          # pochodzenie pól z rangami
GET    /v1/vehicles/{id}/tco?from=&to=

GET    /v1/events?kind=&from=&to=
POST   /v1/events

GET    /v1/contracts | /v1/policies | /v1/damages | /v1/fuel-cards | /v1/tires | /v1/fines | /v1/reminders
POST   /v1/imports                           # wgranie pliku + schemat mapowania
GET    /v1/imports/{id}                      # raport: wczytane, odrzucone, duplikaty

POST   /v1/documents                         # wgranie; OCR jako zadanie w kolejce
GET    /v1/documents/{id}/ocr                # wyniki warstw kaskady + fallback_reason
POST   /v1/documents/{id}/ocr/confirm

GET    /v1/data-quality/conflicts            # rekordy do rozstrzygnięcia
GET    /v1/data-quality/tax-blocking         # pojazdy z brakami blokującymi podatek

POST   /v1/tax/declarations                  # wyliczenie DT-1 dla gminy i roku
GET    /v1/tax/declarations/{id}
POST   /v1/tax/declarations/{id}/correction  # DT-1/A

GET    /v1/finance/postings?period=
POST   /v1/finance/exports                   # paczka do FK; zdarzenie audytowe
GET    /v1/finance/ksef/queue

GET    /v1/reports/{code}?format=json|xlsx|pdf
```

Zasady wspólne: paginacja kursorem, błędy w formacie RFC 9457 (`application/problem+json`), eksport powyżej 10 000 wierszy jako zadanie w tle z wpisem w audycie, zapisy idempotentne przez nagłówek `Idempotency-Key` tam, gdzie klient mobilny może ponowić żądanie.

Kolejki zadań (BullMQ): `ocr`, `imports`, `ksef-send`, `ksef-fetch`, `reminders`, `mv-refresh`, `exports`, `retention`.

---

## Lista kontrolna dla nowej integracji

Zanim klient integracji trafi do gałęzi głównej:

- [ ] Surowa odpowiedź zapisywana w `integr.raw_responses`.
- [ ] Test kontrolny filtra (inna wartość → inny rekord).
- [ ] Odstęp między żądaniami po **każdym** żądaniu, także nieudanym.
- [ ] 429 uruchamia wykładnicze wycofywanie, nie przerywa przebiegu.
- [ ] Błąd logiczny w treści odpowiedzi sprawdzany niezależnie od kodu HTTP.
- [ ] Deduplikacja po identyfikatorze źródłowym.
- [ ] Budżet żądań wypisywany przed startem przebiegu masowego.
- [ ] Poświadczenia z magazynu sekretów, nigdy z pliku w repozytorium.
