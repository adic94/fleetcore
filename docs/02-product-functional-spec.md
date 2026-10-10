# Opis produktu i funkcjonalności

## Zasada porządkująca

Systemy flotowe dzielą dane na trzy sposoby: wokół **pojazdu** (ewidencja), wokół **zlecenia** (transport) albo wokół **dokumentu księgowego** (finanse). Każdy z nich jest poprawny we własnym module i każdy zmusza do przepisywania danych na granicy modułów.

FleetCore wprowadza perspektywę nadrzędną wobec tych trzech: **zdarzenie**.

    zdarzenie floty → koszt → dekret → deklaracja / raport

Tankowanie, szkoda, przegląd, mandat, rata leasingu, kurs transportowy i wydanie telefonu to zdarzenia. Każde ma pojazd albo pracownika, datę, kwotę i dokument źródłowy. Kartoteka pojazdu, rejestr VAT i raport kosztów to **widoki tego samego strumienia**.

Praktyczna konsekwencja, którą trzeba mieć na uwadze przy każdym module: **jeśli jakaś informacja jest wprowadzana po raz drugi, coś w projekcie jest nie tak.**

## Role

| Rola | Kod w bazie | Co robi | Czego nie widzi |
| --- | --- | --- | --- |
| Fleet manager | `manager` | kartoteka pojazdu, przypomnienia, szkody, opony, koszty | płace, dane osobowe spoza floty |
| Dyspozytor | `dispatcher` | zlecenia transportowe, przydział pojazdu i kierowcy | finanse, kadry |
| Księgowość | `accountant` | dekretacja, rejestry VAT, eksport, KSeF | dane lokalizacyjne kierowców |
| Kierowca | `driver` | własny pojazd, zgłoszenie szkody, oświadczenia, protokoły | cudze pojazdy i koszty |
| Przeglądający | `viewer` | odczyt raportów i kartotek w nadanych spółkach, bez zapisu | dane lokalizacyjne, eksport |
| Administrator najemcy | `admin` | użytkownicy, uprawnienia, słowniki, MPK, pola rozszerzalne, odczyt śladu audytowego | dane innych spółek |
| Superadmin | `platform_role = superadmin` | zakładanie najemców, administracja techniczna | **dane klientów** |

Role z kolumny „Kod w bazie" są nadawane **per spółka** w `core.user_company_access`. **Operator wielospółkowy** nie jest osobną rolą — to użytkownik z kilkoma wierszami nadań, w każdej spółce z własną rolą. Dostęp do surowych tras GPS to osobna flaga nadania (`can_view_routes`), nie rola. Wdrożeniowiec po naszej stronie dostaje nadanie roli `admin` z flagą `is_implementer` (pozwala czyścić dane w trybie wdrożenia) na czas wdrożenia, odbierane po jego zakończeniu ([onboarding](14-onboarding-klienta.md)).

Dwa ostatnie wiersze to decyzja architektoniczna, nie wygoda. Szczegóły w [bezpieczeństwie](06-security-privacy-compliance.md) — w skrócie: „dostęp do wszystkich spółek" ma być listą wierszy, którą widać i którą da się odebrać, a nie właściwością roli.

---

## Moduł Flota

Rdzeń systemu. Bez niego reszta nie ma sensu.

### Kartoteka pojazdu

Podział pól na trzy grupy o różnym reżimie:

**Stałe — identyfikacja i dane urzędowe.** Numer rejestracyjny, VIN, marka, model, rodzaj, kategoria homologacyjna, rok produkcji, data pierwszej rejestracji, DMC, masa własna, DMC zespołu, liczba osi, rodzaj zawieszenia, pojemność i moc silnika, rodzaj paliwa, norma emisji, liczba miejsc.

**Organizacyjne.** Spółka, oddział, MPK, obiekt kontrolingowy, użytkownik, status.

**Rozszerzalne.** Pola definiowane per najemca, typowane (tekst, liczba, data, słownik), widoczne w siatce i filtrach.

Trzecia grupa nie jest udogodnieniem. Kartoteka pojazdu w systemie odniesienia ma **478 kolumn** — bez pól rozszerzalnych po roku eksploatacji zabraknie miejsca na kolejne „pole na numer umowy serwisowej", a wtedy użytkownik zacznie wpisywać dane w pole „Uwagi".

**Pola podatkowe mają osobny reżim.** Zmiana wymaga wskazania dokumentu źródłowego i trafia do śladu audytowego. Które to pola i dlaczego — [model danych](05-data-model-and-analytics.md).

### Identyfikacja pojazdu

**Tożsamością pojazdu jest VIN, nie numer rejestracyjny.**

Numer rejestracyjny zmienia się przy przerejestrowaniu, a stary dokument zostaje w dokumentacji. Scalanie po numerze dało w rzeczywistych danych **26 pojazdów występujących pod więcej niż jedną tablicą — 53 wiersze zamiast 26** — i zawyżyło sumę podatku o kilkanaście tysięcy złotych.

Numer rejestracyjny jest **atrybutem z historią**, przechowywanym w osobnej tabeli z zakresem dat.

### Rejestry towarzyszące

| Rejestr | Zawartość |
| --- | --- |
| Umowy | leasing, najem, kredyt, umowy z dostawcami, harmonogramy rat, limity przebiegu |
| Polisy | OC, AC, NNW, GAP, assistance; okresy, składki, raty, udziały własne |
| Szkody | zgłoszenie, likwidacja, kosztorys, udział własny, regres, wina |
| Opony | komplety, sezonowość, przechowanie, przebiegi, pozycja na pojeździe |
| Karty paliwowe | przypisanie w czasie, limity, blokady, rozliczenie limitów |
| Liczniki | stany, źródło odczytu, korekty |
| Mandaty | wykroczenia, wskazanie kierowcy, punkty, terminy |
| Autoryzacje napraw | zgody, limity kwotowe, pozycje kosztorysu |
| Przypomnienia | przeglądy, badania, końce polis i umów — wg daty **lub przebiegu** |

Przypomnienia wg przebiegu, nie tylko daty, są wymaganiem: przegląd okresowy pojazdu ciężarowego wypada co określoną liczbę kilometrów.

### Protokoły

Wydanie i zdanie pojazdu oraz sprzętu. **Dokument z podpisem na urządzeniu mobilnym i zdjęciami**, nie wydruk do podpisania długopisem.

Zdjęcia z protokołu zdania są wejściem do rejestru szkód — to samo źródło, nie przepisywanie.

Osobno od protokołu przekazania istnieją **oględziny pojazdu** — inna czynność, inny formularz, inny moment.

---

## Moduł Rent

Dla firm prowadzących wynajem krótko- i długoterminowy oraz CFM.

- Cenniki: godzinowe, dobowe, miesięczne, długoterminowe; grupy rabatowe; cenniki indywidualne per klient.
- Rezerwacje i dostępność, pojazdy zastępcze, przydziały.
- Zlecenia najmu, kaucje, rozliczenie nadprzebiegu i szkód.
- Faktury najmu, należności, import wyciągów bankowych i dopasowanie wpłat.
- Miejsca parkingowe: przydział i optymalizacja wykorzystania.

> **Słownik statusów definiujemy raz.** W systemie produkcyjnym rezerwacje miały dwie tabele o podobnych nazwach i **różnych słownikach statusów**. Interfejs oferował wartość, której ograniczenie w bazie nie dopuszczało — każdy zapis kończył się błędem. Drugi, niezgłoszony objaw: istniejące wiersze renderowały się jako surowa wartość techniczna, bo mapa etykiet nie miała takiego klucza.
>
> Lista dopuszczalnych statusów w bazie i lista etykiet w interfejsie muszą pochodzić z jednego miejsca.

---

## Moduł Transport

Dla firm prowadzących transport zarobkowy. **Moduł warunkowy** — budowany tylko wtedy, gdy firma faktycznie prowadzi taką działalność.

- Zlecenia transportowe i podzlecenia, kartoteki transportowe.
- Przydział pojazdu, naczepy i kierowcy.
- Dokumentacja przewozowa: CMR, listy przewozowe, dokumenty OCS i OCP.
- Rozliczenie kursu: frachty, koszty paliwa, opłaty drogowe, diety, palety.
- Ofertowanie, reklamacje i niezgodności.
- Zlecanie przewoźnikom zewnętrznym.

Naczepa jest **pojazdem o rodzaju „przyczepa"**, nie osobną encją. To istotne podatkowo: przyczepy i naczepy podlegają DT-1, gdy **łącznie z pojazdem silnikowym** mają DMC od 7 t, i mają własną tabelę stawek, inną niż samochód ciężarowy. Od 12 t (łącznie) stawka zależy od liczby osi i rodzaju zawieszenia.

**Przed rozpoczęciem tego modułu wymagany jest warsztat z dyspozytorem.** Lista modułów systemów odniesienia mówi, *co* obsługują, nie *jak* wygląda rejestracja zlecenia.

### Czego w tym module nie ma

Spedycja morska i lotnicza, obsługa celna (agencja, skład celny, gwarancje), zgłoszenia fitosanitarne. Uzasadnienie w [założeniach projektu](01-project-brief.md) — w skrócie: regulowana dziedzina, bez agenta celnego w zespole budowa jest bezcelowa.

---

## Moduł Finanse

Zakres związany z flotą. Pełna księgowość pozostaje poza produktem.

- Rejestry VAT zakupu i sprzedaży.
- **Proporcja odliczenia VAT dla pojazdów: 0 / 50 / 100%** — wymaganie wynikające z polskich przepisów o pojazdach używanych do celów mieszanych.
- Środki trwałe i amortyzacja — pojazdy jako środki trwałe z planem amortyzacji.
- Dekretacja kosztów floty na MPK i konta, eksport do systemu FK.
- Import zapłat, rozrachunki, generowanie przelewów.
- JPK.
- KSeF: wysyłka i odbiór faktur, format FA(3).
- Rozliczanie kosztów pojazdów prywatnych do celów służbowych (ryczałty, kilometrówka).

> **KSeF pisany od zera, wg `open-api.json` Ministerstwa Finansów.** Nie przenosić istniejącej integracji z systemu odniesienia — celuje w API, którego już nie ma. Szczegóły i aktualne adresy: [integracje](04-api-integrations.md).

---

## Moduł Podatki

**Nie ma odpowiednika w żadnym z systemów odniesienia.** Główna przewaga produktu.

- **DT-1 i DT-1/A**: kategoria pojazdu, stawka, deklaracja, korekty, miesiące posiadania.
- **Stawki per gmina**, z uchwał rady. Struktura klucza: rodzaj pojazdu + podstawa masy (DMC pojazdu albo DMC zespołu) + przedział masy + liczba osi + rodzaj zawieszenia; dla autobusów liczba miejsc.
- **Opłata środowiskowa** — klucz trójwymiarowy: paliwo × norma EURO × **klasa pojazdu**.
- **Raport CO2** i wskaźniki ESG.

### Reguły domenowe, których nie wolno pominąć

**Które pojazdy w ogóle podlegają podatkowi** (ustawa o podatkach i opłatach lokalnych):

| Rodzaj | Próg | Od czego zależy stawka |
| --- | --- | --- |
| Samochód ciężarowy | DMC powyżej 3,5 t | do 12 t: przedział DMC; od 12 t: DMC, liczba osi, zawieszenie |
| Ciągnik siodłowy i balastowy | DMC **zespołu** od 3,5 t | do 12 t: przedział DMC zespołu; od 12 t: DMC zespołu, liczba osi, zawieszenie |
| Przyczepa i naczepa | DMC **łącznie z pojazdem silnikowym** od 7 t | do 12 t: przedział; od 12 t: DMC łącznie, liczba osi, zawieszenie |
| Autobus | każdy | liczba miejsc do siedzenia poza miejscem kierowcy |

**Od 12 ton stawka zależy od liczby osi i rodzaju zawieszenia** (pneumatyczne lub uznane za równoważne vs inne). Poniżej progu kategorię wyznacza sama masa i rodzaj pojazdu. To znaczy, że liczba osi i zawieszenie są polami krytycznymi tylko dla części floty — i tylko dla tej części ich brak blokuje wyliczenie.

> Tabelę trzeba potwierdzić z doradcą podatkowym przed fazą 2 — ma pierwszeństwo przed silnikiem przenoszonym z TaxOrder Pro, jeśli się różnią. Przyczepy rolnicze używane wyłącznie w działalności rolniczej są zwolnione.

**Pojazdy specjalne są zwolnione** niezależnie od pozostałych parametrów. Guard musi siedzieć w silniku podatkowym, nie w warstwie prezentacji.

**Podatek liczy się za miesiące posiadania**, nie za rok. Pojazd sprzedany w maju generuje należność za 5 miesięcy.

> **Klasa pojazdu w opłacie środowiskowej to nie szczegół.** Tabela stawek ma trzy wymiary. Dla oleju napędowego EURO 5: pojazd osobowy 5,76 zł/Mg, do 3,5 t inny niż osobowy 6,82, powyżej 3,5 t **9,19**. Pominięcie klasy pojazdu zaniża należność o około 40%, a wynik wygląda wiarygodnie.
>
> Drugi, niezależny brak: obwieszczenie ze stawkami **nie podaje gęstości paliw**, więc przeliczenie litrów na megagramy wymaga osobnego źródła. Do czasu uzupełnienia obu rzeczy wyliczenie opłaty ma **odmawiać**, a nie szacować.

---

## Moduł Zasoby

- Wyposażenie pracownika: sprzęt, telefony, karty, odzież.
- Protokoły wydania i zdania, stan magazynowy.
- Import faktur billingowych, rozliczenie limitów telefonicznych.
- Uprawnienia pracowników i terminy ich ważności, nieobecności.
- **Oświadczenia**: o używaniu pojazdu do celów służbowych, zgody, potwierdzenia zapoznania z regulaminem.

---

## Moduł Telematyka

- Pozycje, trasy, przebiegi z GPS jako źródło stanów liczników.
- Rozliczanie jazd prywatnych i ryczałtów.
- **Geofency stacji paliw — weryfikacja tankowań z kartami paliwowymi.**
- **Czas pracy z obrotów silnika, nie z zapłonu.**

Dwa ostatnie punkty wymagają komentarza, bo odróżniają moduł użyteczny od dekoracyjnego.

Weryfikacja przez geofency to jeden z niewielu mechanizmów, który **wykrywa nadużycie kartą paliwową**, a nie tylko je rejestruje: tankowanie bez pojazdu w promieniu stacji w oknie ±15 minut trafia na listę do wyjaśnienia.

Czas pracy z obrotów ma znaczenie dla pojazdów pracujących **na postoju z napędem pomocniczym** (asenizacyjne, dźwigi, agregaty). Dla nich zapłon nie opisuje pracy.

---

## Aplikacja mobilna kierowcy

Nie jest osobnym modułem — jest **kanałem dostępu do modułów Flota i Transport**.

Kierowca: zgłasza wykonanie zadania (załadunek, wyładunek, tankowanie), przegląd i badanie techniczne, podaje stan licznika, robi zdjęcia, podpisuje protokół wydania i zdania, zgłasza szkodę.

Dyspozytor: przekazuje zlecenie, otrzymuje status realizacji.

> **Praca offline jest wymaganiem otwartym.** Protokoły w terenie sporządza się często bez zasięgu. Albo aplikacja działa offline z synchronizacją, albo funkcja protokołów mobilnych jest bezużyteczna. Decyzja wpływa na architekturę klienta — patrz [założenia projektu](01-project-brief.md).

---

## Raporty

Definicja raportu **żyje w bazie, nie w pliku na stacji roboczej**. Konfiguracja kolumn, filtrów i grupowania jest przypisana do użytkownika i najemcy.

Zestaw startowy, odtworzony z raportów faktycznie używanych w systemach odniesienia:

- raport pojazdów (pojazdy, marki, użytkownicy),
- rozliczenie limitów na kartach paliwowych,
- rozliczenie ryczałtów za kilometry prywatne — z podsumowaniem na pracownika **i** z rozbiciem na pojazdy,
- zestawienie kończących się ubezpieczeń,
- kontrola nadprzebiegu z umów,
- opony na pojazdach, przebiegi opon,
- eksport rejestru kosztów do księgowości,
- raport uprawnień operatorów,
- **TCO na pojazd** i koszt na kilometr,
- **lista pojazdów z brakami blokującymi wyliczenie podatku**.

Dwa ostatnie nie mają odpowiednika w systemach odniesienia.

---

## Ekrany główne

Lista ekranów, od których zaczyna się projekt interfejsu. Każdy ekran listy to siatka z konfiguracją kolumn zapisaną w bazie (patrz „Raporty"), filtrami i eksportem — eksport jest zdarzeniem audytowym.

| Ekran | Dla kogo | Co pokazuje | Faza |
| --- | --- | --- | --- |
| **Pulpit floty** | fleet manager | terminy w ciągu 30 dni (przeglądy, polisy, umowy), otwarte szkody, pojazdy z brakami blokującymi podatek, alerty kart paliwowych | 1 |
| **Lista pojazdów** | fleet manager, księgowość | siatka kartotek z polami rozszerzalnymi, filtr po spółce/oddziale/MPK/statusie | 1 |
| **Kartoteka pojazdu** | fleet manager | zakładki: dane urzędowe (z pochodzeniem pól), organizacyjne, oś czasu zdarzeń, umowy, polisy, szkody, opony, karty, dokumenty, TCO | 1 |
| **Oś czasu pojazdu** | fleet manager | wszystkie zdarzenia z kwotami i dokumentem źródłowym, filtr po typie | 1 |
| **Import** | fleet manager, administrator | wgranie pliku, mapowanie kolumn (schemat zapisany per dostawca), podgląd, raport odrzuceń i duplikatów | 1 |
| **Dokumenty i OCR** | fleet manager | kolejka dokumentów, wynik warstwy kaskady, powód zejścia na niższą warstwę, zatwierdzenie odczytu | 1 |
| **Rekordy do rozstrzygnięcia** | fleet manager | konflikty źródeł tej samej rangi, rekordy wewnętrznie sprzeczne, pola wypełnione hurtem | 1 |
| **Deklaracja DT-1** | księgowość | pozycje per pojazd, kategoria, stawka z uchwały, miesiące posiadania, kolumna braków blokujących; korekta DT-1/A | 2 |
| **Dekretacja i eksport FK** | księgowość | koszty do zadekretowania, MPK, konta, proporcja VAT 0/50/100%, paczka eksportu | 2 |
| **KSeF** | księgowość | faktury wysłane/odebrane, statusy, kolejka ponowień z wiekiem najstarszej pozycji | 2 |
| **Wydanie i zdanie** (mobilny) | kierowca | protokół ze zdjęciami i podpisem, stan licznika | 3 |
| **Weryfikacja tankowań** | fleet manager | tankowania bez pojazdu w geofencu stacji ±15 min | 3 |
| **Rezerwacje i najem** | dział najmu | kalendarz dostępności, rezerwacje, zlecenia, kaucje | 4 |
| **Zlecenia transportowe** | dyspozytor | lista i karta zlecenia, przydział pojazdu/naczepy/kierowcy, dokumenty, rozliczenie kursu | 5 |
| **Administracja najemcy** | administrator | użytkownicy, role, dostępy do spółek, moduły, słowniki, definicje pól rozszerzalnych | 0 |

Ekrany modułów warunkowych (fazy 4–5) projektuje się dopiero po warsztatach z praktykami.
