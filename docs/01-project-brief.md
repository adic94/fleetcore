# Założenia projektu

## Jednym akapitem

FleetCore to system zarządzania flotą budowany od zera, łączący w jednym produkcie ewidencję pojazdów, wynajem, zlecenia transportowe i rozliczenia podatkowo-księgowe. Powstaje, bo firma z flotą 100–1000 pojazdów prowadzi ją dziś w kilku niepowiązanych programach, wprowadza te same dane wielokrotnie i nie potrafi odpowiedzieć, ile kosztuje konkretny pojazd. FleetCore zapisuje zdarzenie floty raz i udostępnia je wszystkim modułom.

## Co konkretnie jest zepsute dziś

Nie ogólniki, tylko rzeczy zmierzone na pierwszej, własnej flocie. Liczby pokazują **klasy problemów**, nie skalę produktu — u każdego klienta liczba pojazdów i kwoty będą inne, a te same klasy błędów się powtórzą.

| Problem | Jak to wyglądało u nas |
| --- | --- |
| Ten sam pojazd w wielu ewidencjach | w dokumentacji rozpoznano **26 pojazdów pod więcej niż jedną tablicą** (53 wiersze zamiast 26) |
| Dane podatkowe zbierane ręcznie, poza systemami | podatek od środków transportowych liczony w arkuszach, poza wszystkimi programami |
| Braki danych blokujące wyliczenie | **134 pojazdy** bez kompletu pól; 117 bez DMC, 17 powyżej 12 t bez liczby osi |
| Cicha zaniżona stawka | na próbce 24 pojazdów **5 miało zaniżoną kategorię** — wyłącznie z braku liczby osi |
| Pole wpisane hurtem, udające dane | rodzaj zawieszenia: **wszystkie 217 pojazdów ma „pneumatyczne"** — razem z motocyklem i przyczepą |

Ostatnie dwa wiersze opisują tę samą klasę problemu i ona jest właściwym uzasadnieniem projektu. **Od 12 t stawka podatku zależy od liczby osi i rodzaju zawieszenia.** Przy braku liczby osi silnik przyjmuje wartość domyślną, czyli najniższą stawkę w przedziale. Deklaracja wychodzi kompletna, wiarygodna i zaniżona.

Puste pole widać. Błędne — nie.

## Wizja produktu

Jedna zasada, z której wynika cała reszta:

    zdarzenie floty → koszt → dekret → deklaracja / raport

Tankowanie, szkoda, przegląd, mandat, rata leasingu, kurs transportowy i wydanie telefonu to **zdarzenia**. Każde ma pojazd albo pracownika, datę, kwotę i dokument źródłowy. Kartoteka pojazdu, rejestr VAT i raport kosztów to **widoki tego samego strumienia**, a nie osobne bazy.

To odróżnia FleetCore od systemów odniesienia, które dzielą dane inaczej: wokół pojazdu, wokół zlecenia albo wokół dokumentu księgowego. FleetCore wprowadza perspektywę nadrzędną wobec tych trzech.

## Dla kogo

| Odbiorca | Potrzeba |
| --- | --- |
| Firma z własnym taborem, 100–1000 pojazdów | jedna ewidencja zamiast czterech, koszt na pojazd |
| Operator obsługujący wiele spółek | wielonajemcowość z twardą izolacją danych |
| Wypożyczalnia i CFM | cenniki, rezerwacje, rozliczenia najmu |
| Firma transportowa | zlecenia, dokumentacja przewozowa, rozliczenie kursu |

Architektura od pierwszego dnia zakłada **wielu najemców**, bo jedno konto operatora obsługuje dziś 6 spółek klienckich. To nie jest funkcja na później — dokładanie izolacji danych do działającego systemu jest przepisywaniem, nie rozszerzaniem.

### Model produktu

FleetCore budujemy **dla siebie i dla przyszłych klientów zewnętrznych**. Nie ma sponsora ani zewnętrznego finansowania — pierwszym wdrożeniem jest własna flota, kolejnymi klienci.

Z tej decyzji wynikają trzy wymagania, które nie są już opcją:

- **wielonajemcowość z twardą izolacją** — klient zewnętrzny nigdy nie zobaczy danych innego klienta ani naszych;
- **licencjonowanie modułów** (`core.company_modules`) — klient płaci za moduły, których używa; firma bez transportu nie kupuje modułu Transport;
- **sprawy prawne sprzedaży** — licencja, umowa, regulamin świadczenia usługi, polityka prywatności, umowa powierzenia przetwarzania danych z każdym klientem ([zasoby](13-resources-and-prerequisites.md)).

Własna flota jest jednocześnie pierwszym klientem i środowiskiem weryfikacji: kryteria sukcesu faz 1 i 2 mierzymy na jej danych, zanim system trafi do kogokolwiek z zewnątrz.

## Kryteria sukcesu

Mierzalne, nie uznaniowe.

### Faza 1 — moduł Flota

**Migracja danych przez arkusze importu odtwarza kartotekę pojazdu bez ręcznych poprawek.** Sprawdzalne: liczba pojazdów, suma kosztów i liczba rekordów w każdym rejestrze zgadzają się ze źródłem.

### Faza 2 — podatki

**Suma podatku DT-1 policzona przez FleetCore zgadza się co do złotówki** z niezależnym wyliczeniem na tych samych danych.

Punkt odniesienia istnieje: dzisiejsze wyliczenie różni się od bazy produkcyjnej o **0,24%** (552 zł na 229 104 zł), a cała różnica jest wyjaśniona brakami liczby osi. Po migracji różnica ma wynosić zero — braki mają być albo uzupełnione, albo **jawnie oznaczone jako blokujące**, nigdy ciche.

### Całość

**Żadna liczba w systemie nie ma dwóch źródeł.** Jeśli wskaźnik emisji, stawka podatku albo definicja „pojazdu czynnego" istnieje w dwóch miejscach, jest to błąd projektowy do naprawienia, a nie szczegół implementacyjny.

## Zakres — co wchodzi

Moduły: Flota, Rent, Transport, Finanse, Podatki, Zasoby, Telematyka. Rozpisane w [opisie produktu](02-product-functional-spec.md).

## Zakres — czego świadomie nie budujemy

Każda pozycja to decyzja do zakwestionowania, nie przeoczenie.

| Funkcja | Dlaczego nie |
| --- | --- |
| **Kadry i płace** | nieskończone śledzenie zmian w ZUS i PIT, przy module bez przewagi konkurencyjnej; kupić gotowy albo zostawić istniejący |
| **Spedycja morska, lotnicza, obsługa celna** | regulowana dziedzina z własnymi organami i procedurami; **bez agenta celnego w zespole budowa jest bezcelowa, nie tylko ryzykowna** |
| **Pełna księgowość (KPiR, ryczałt)** | jak wyżej; FleetCore robi rejestry VAT i dekretację, resztę eksportuje do FK |
| **Osobny klient desktopowy** (instalator `.exe`/`.dmg` z własnym kodem) | Windows, macOS i Linux dostają ten sam panel webowy instalowany jako aplikacja (PWA); osobny kod desktopowy to druga aplikacja do utrzymania bez nowych funkcji. Jeśli klienci zażądają instalatora, panel opakowuje się w Tauri bez przepisywania |
| **Hurtownia danych i osobne BI** | przy tej skali widoki materializowane wystarczą; osobna hurtownia to drugie miejsce, w którym liczby mogą się rozjechać |
| **Szkolenia pracowników** | osobna dziedzina, słabo powiązana z flotą |

Wyjątek od wiersza o księgowości: **środki trwałe i amortyzacja pojazdów** zostają w zakresie, bo są mocno związane z flotą.

## Założenia, które trzeba potwierdzić przed kodowaniem

Nie zgadujemy po cichu. Lista rzeczy, których nie da się rozstrzygnąć z materiałów:

1. **Praca offline aplikacji mobilnej.** Protokoły wydania i zdania pojazdu sporządzane są w terenie, często bez zasięgu. Albo działają offline, albo cała funkcja jest bezużyteczna. Wpływa na architekturę klienta mobilnego.
2. **Liczba równoczesnych użytkowników na najemcę.** Wpływa na sposób skalowania warstwy API.
3. **Czy dane muszą pozostać w Polsce.** Jeśli tak, wyklucza część dostawców chmury.
4. **Zakres transportowy.** Lista modułów systemów odniesienia jest znana, ale przepływy pracy — nie. Warsztat z dyspozytorem przed fazą transportową jest warunkiem koniecznym.
Punkt 3 rozstrzyga właściciel, 1 i 4 — praktycy razem z zespołem, 2 wynika z pierwszego wdrożenia.

**Rozstrzygnięte:**

- produkt będzie sprzedawany klientom zewnętrznym — patrz „Model produktu" wyżej;
- **platformy** (10.10.2026): system działa na Windows, macOS, Linux, iOS, Android i w przeglądarce:

| Platforma | Rozwiązanie |
| --- | --- |
| Przeglądarka (każdy system) | panel webowy — React |
| Windows, macOS, Linux | ten sam panel instalowany jako aplikacja (PWA): ikona, własne okno, aktualizacje bez instalatora |
| iOS, Android | aplikacja natywna w **React Native (Expo)** — kierowca i fleet manager w terenie; aparat, podpis, praca offline; publikacja w App Store i Google Play |
| Tablety | panel webowy w wersji responsywnej + aplikacja mobilna |

  Aplikacja mobilna jest natywna, bo protokoły w terenie wymagają pracy bez zasięgu, aparatu i podpisu — to rozstrzyga też punkt 1 na korzyść architektury offline-first po stronie mobilnej. Panel i aplikacja mobilna dzielą typy i klienta API (`packages/contracts`).

## Szacunek pracochłonności

Szacunek z jawnymi założeniami, nie wycena. Zakłada zespół 3–4 osób, patrz [zasoby](13-resources-and-prerequisites.md). Numeracja faz jest wspólna dla całej dokumentacji — źródłem jest [roadmapa](07-roadmap.md).

| Faza | Zakres | Osobomiesiące |
| --- | --- | --- |
| 0 | Fundament: repozytorium, CI, najemcy, RLS, uwierzytelnianie, dokumenty | 2–3 |
| 1 | Moduł Flota + migracja danych | 8–12 |
| 2 | Podatki i dekretacja | 4–6 |
| 3 | Zasoby, telematyka, aplikacja mobilna | 4–6 |
| 4 | Rent / CFM — warunkowa | 6–9 |
| 5 | Transport — warunkowa | 6–9 |

Realistyczne minimum, żeby system zastąpił dotychczasową ewidencję: **fazy 0–2, czyli 14–21 osobomiesięcy.**

Fazy 4 i 5 są warunkowe — budowane wtedy, gdy my albo klient faktycznie prowadzimy wynajem lub transport zarobkowy.

## Co jest już gotowe i nie wymaga pisania od nowa

Nie zaczynamy od czystej kartki. Elementy sprawdzone w produkcji, do przeniesienia:

| Zasób | Stan |
| --- | --- |
| Silnik podatkowy DT-1 | działa; kategorie, progi, zwolnienia; zgodność z bazą 0,24% |
| Stawki gminne | zweryfikowane **45 z 45 pozycji** z uchwałą rady miasta |
| Usługa OCR dowodów rejestracyjnych | parser geometryczny, 8–11 s na dokument, korekcja orientacji strony |
| Dekodowanie kodu Aztec z dowodu | pełna ścieżka sprawdzona end-to-end, 17/17 pól |
| Importy kart paliwowych i telematyki | działają |
| Scalanie danych z wielu źródeł z rangami | działa na 907 pojazdach |
| Zestaw bramek testowych | do przeniesienia, nie do napisania |

Szczegóły i lokalizacja kodu: [systemy odniesienia](12-source-systems.md), rozdział o TaxOrder Pro.
