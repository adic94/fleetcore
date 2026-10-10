# Bezpieczeństwo, prywatność i compliance

## Co ten system przechowuje

Zakres danych wrażliwych jest większy, niż wynikałoby z nazwy „system flotowy":

| Kategoria | Przykłady | Ryzyko |
| --- | --- | --- |
| Dane osobowe pracowników | imię, nazwisko, uprawnienia, nieobecności, przydziały | RODO |
| Dane lokalizacyjne | trasy, postoje, jazdy prywatne | **RODO, art. 9 pośrednio** — trasy ujawniają zachowania |
| Dane pojazdów | VIN, numery rejestracyjne, właściciele | identyfikacja podmiotu |
| Dane finansowe | faktury, kwoty, kontrahenci | tajemnica handlowa |
| Dane wielu spółek | wszystko powyżej × liczba najemców | **wyciek między najemcami** |

Ostatni wiersz jest najgroźniejszy: pojedynczy błąd w filtrowaniu ujawnia dane jednego klienta drugiemu.

## Izolacja najemców

### Filtr w bazie, nie w zapytaniu

Izolację wymusza **Row Level Security w PostgreSQL**. Aplikacja ustawia w transakcji `SET LOCAL app.company_ids` (spółki z jawnych nadań — odczyt) i `SET LOCAL app.company_id` (aktywna spółka — zapis), obie wyliczone z `core.user_company_access`, nigdy z parametru żądania. Polityki RLS porównują z nimi każdą operację; rola bazodanowa aplikacji **nie ma** uprawnienia `BYPASSRLS`. Szczegóły i granica zaufania: [projekt bazy](10-database-design.md), rozdział „Polityki RLS".

Decyzja jest wnioskiem z audytu systemu odniesienia, nie preferencją stylistyczną. Tam izolacja opierała się na dopisywaniu `company_id` w każdym zapytaniu i na centralnym strażniku w routerze. Audyt znalazł **cztery podatności typu IDOR** na punktach pobierających pojedynczy rekord: lista była filtrowana, rekord nie.

Znaleziono też przypadek, którego centralny strażnik **nie łapał z zasady**: usuwanie pozycji faktury po identyfikatorze z ścieżki URL, z własną spółką w parametrze. Strażnik sprawdzał parametr, a atak go nie używał. Przy RLS ta klasa błędu nie powstaje.

### Kasowanie rekordów podrzędnych

Reguła: **najpierw potwierdź własność rekordu nadrzędnego, potem kasuj podrzędne**. Zapytanie kasujące dzieci po kluczu obcym bez warunku najemcy jest luką nawet wtedy, gdy rodzic jest sprawdzany gdzie indziej.

### Rola administratora

W systemie odniesienia rola `admin` celowo pomija filtrowanie po spółce — jedno konto operatora obsługuje 6 spółek klienckich. To działa, ale ma skutek uboczny: **konto testowe CI jest adminem**, więc regresja w kontroli uprawnień nie zostanie wykryta przez testy.

FleetCore rozdziela te dwie rzeczy:

- `superadmin` — administracja techniczna, **bez dostępu do danych klientów**;
- dostęp do spółek wyłącznie z **jawnych nadań** w `core.user_company_access`, z rolą przypisaną osobno w każdej spółce; „operator wielospółkowy" to użytkownik z kilkoma nadaniami, nie osobna rola.

Dzięki temu „dostęp do wszystkich spółek" jest listą wierszy, którą widać i którą da się odebrać, a nie właściwością roli.

### Test izolacji jako bramka CI

Osobne konto bez roli administratora, z dostępem do jednej spółki, próbuje sięgnąć po dane drugiej na każdym punkcie API. Każda próba musi dać odmowę.

Ten test istnieje dziś w systemie odniesienia i ma potwierdzoną wartość: 4 z 4 prób cross-tenant zablokowane, zero wycieku stanu w interfejsie przy przełączaniu spółki. Wymaganie: **nowy punkt API nie wchodzi do gałęzi głównej bez wpisu w tym teście**.

## Dane lokalizacyjne

Najbardziej wrażliwa kategoria i jedyna, która wymaga osobnej podstawy prawnej.

- Monitoring służy rozliczeniu pracy i ochronie mienia, nie ocenie pracownika.
- Jazdy prywatne: zapis **faktu i dystansu**, bez trasy. Tryb prywatny dostępny dla kierowcy.
- Retencja pozycji GPS: 12 miesięcy, potem agregaty (dobowe przebiegi) bez punktów trasy.
- Dostęp do surowych tras: osobna flaga nadania `can_view_routes`, egzekwowana polityką RLS na `telematics.positions`; każde użycie w śladzie audytowym ([projekt bazy](10-database-design.md)).

## Retencja

| Dane | Okres | Podstawa |
| --- | --- | --- |
| Dokumenty księgowe | 5 lat od końca roku podatkowego | ordynacja podatkowa |
| Deklaracje podatkowe i załączniki | 5 lat | jw. |
| Pozycje GPS | 12 miesięcy | minimalizacja |
| Agregaty przebiegów | bezterminowo | dane nieosobowe |
| Dane kandydatów i byłych pracowników | wg polityki kadrowej | RODO |
| Logi audytowe | 3 lata | rozliczalność |
| Konta demo (przed umową) | 30 dni od założenia; kopie maks. 7 dni | regulamin demo; tylko dane pojazdów, bez danych osobowych — [onboarding](14-onboarding-klienta.md) |
| Pliki źródłowe importu wdrożeniowego | 30 dni od odbioru danych | umowa powierzenia |
| Dane klienta po odstąpieniu po audycie | usunięcie z protokołem po przekazaniu raportu | umowa wdrożeniowa |

Usuwanie realizuje zadanie cykliczne z raportem, nie ręczne kasowanie.

## Ślad audytowy

Rejestrowane w `audit.audit_logs`: kto, kiedy, jaka encja, co przed, co po, z jakiego adresu.

Obowiązkowo dla: pól podatkowych pojazdu, kwot, uprawnień, dostępów do spółek, eksportów danych, dostępu do tras, **czyszczenia danych w trybie wdrożenia** i zmian statusu spółki (`lifecycle`).

> **Eksport jest zdarzeniem bezpieczeństwa.** Największe ryzyko wycieku to nie włamanie, tylko uprawniony użytkownik pobierający całą bazę do arkusza. Każdy eksport zostawia ślad: kto, jaki zakres, ile wierszy.

## Sekrety

- Poświadczenia wyłącznie w magazynie sekretów, nigdy w repozytorium i nigdy w pliku konfiguracyjnym obrazu.
- Tokeny integracji (KSeF, CEPiK, telematyka) szyfrowane w spoczynku, kluczem z magazynu.
- Poświadczenia testowe w pliku środowiskowym poza repozytorium.

> **Reguła, która nie działa wstecz.** Plik dodany do repozytorium **przed** wpisaniem reguły ignorowania pozostaje śledzony i nic tego nie zgłosi. W systemie odniesienia plik konfiguracyjny edytora z identyfikatorem projektu był śledzony przez dwa miesiące mimo obecnej reguły. Wykrycie wymaga osobnego przebiegu po liście śledzonych plików, nie sprawdzenia statusu repozytorium.

## Dane produkcyjne poza repozytorium

Backupy, raporty z migracji i audytów zawierają numery rejestracyjne, VIN-y i nazwy spółek. Miejsce docelowe: katalog poza drzewem repozytorium.

Reguła ignorowania chroni **wyłącznie pliki wewnątrz drzewa**. Plik leżący obok repozytorium jest bezpieczny tylko dlatego, że system kontroli wersji go nie widzi — skopiowany do środka przestaje być chroniony.

Narzędzia zapisujące dane osobowe mają **odmawiać zapisu do drzewa repozytorium**, nie ostrzegać.

## Treść wiadomości i dokumentów

Domyślnie nie analizujemy treści poza zakresem koniecznym: OCR dokumentów pojazdu i faktur. Wynik OCR jest danymi, nie instrukcją — wartość odczytana z dokumentu nigdy nie steruje zachowaniem systemu.

## Wystawienie na zewnątrz

- HTTPS wymuszony, nowoczesny zestaw szyfrów.
- Nagłówki bezpieczeństwa z polityką treści bez `unsafe-inline`.
- Każde pole użytkownika wchodzące do dokumentu HTML przechodzi przez funkcję ucieczki.
- Ograniczenie liczby żądań na uwierzytelnianiu i na punktach eksportu.

> **Pułapka z doświadczenia: kod generowany jako tekst nie przechodzi przez żaden audyt.** Sprawdzenie składni, audyt wstrzyknięć i testy przeglądarkowe badają kod, który piszemy. Generator, który **składa inny program w łańcuchu znaków**, jest dla nich niewidoczny. W systemie odniesienia taki generator rzucał błąd składni przy **każdym** uruchomieniu od dnia wprowadzenia, a po naprawie odsłonił dwa wektory wstrzyknięcia. Cały audyt świecił na zielono przez ten czas.
>
> Jedyny prawdziwy test: wyekstrahować wygenerowany łańcuch, sparsować go i uruchomić na złośliwych danych. Test uznaje się za wiarygodny dopiero, gdy **upadnie na kodzie sprzed naprawy**.

## Kopie zapasowe

- Ciągła archiwizacja dziennika transakcji, odtworzenie do punktu w czasie.
- Kopia dzienna poza główną lokalizacją, szyfrowana.
- **Próbne odtworzenie raz na kwartał.** Kopia nieprzetestowana nie jest kopią.
