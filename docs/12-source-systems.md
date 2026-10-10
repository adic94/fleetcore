# Systemy odniesienia

Zakres FleetCore nie jest wymyślony — pochodzi z analizy czterech systemów pracujących produkcyjnie oraz systemów, na których firma pracuje dziś (rozdział 5). Ten dokument opisuje, co każdy z nich wnosi, co warto przejąć i czego świadomie nie odtwarzamy.

> **Uwaga o nazewnictwie, żeby nie było pomyłki.** W materiałach źródłowych występują dwa różne „TaxPro":
>
> - **TaxOrder Pro** — nasz własny system, opisany w rozdziale 4. To z niego przenosimy kod.
> - **TaxPro (ADAD Systems)** — obce oprogramowanie księgowe dla biur rachunkowych (KPiR, ryczałt, faktury, kadry). Nie jest systemem flotowym i **nie jest źródłem wymagań dla FleetCore**, poza ogólnym potwierdzeniem, jakie rozliczenia księgowe są w tej dziedzinie potrzebne.
>
> Gdy w dokumentacji pada „nasz system", chodzi zawsze o TaxOrder Pro.

## Granica prawna i techniczna

Obowiązuje we wszystkich fazach projektu:

- **Nie dekompilujemy** plików wykonywalnych żadnego producenta.
- **Nie kopiujemy** schematów baz danych, kodu, grafiki ani nazw handlowych.
- **Nie łączymy się** bezpośrednio z bazą danych cudzego systemu.
- Migracja danych idzie wyłącznie przez **publiczne arkusze importu i eksportu** udostępniane przez producenta klientowi.

Odtwarzamy **funkcje i przepływy pracy** — to, że system flotowy potrzebuje rejestru polis, nie jest niczyją własnością. Implementacja jest nasza.

---

## 1. Softra FLOTA

Producent działa od 1995 roku, linia produktowa: FLOTA Commandor (fleet manager), FLOTA Rent (wypożyczalnie), FLOTA Pro CFM (najem długoterminowy), CarSharing, oprogramowanie administracyjne (telefony, delegacje, budynki).

**To najlepiej rozpoznany system z całej czwórki**, bo analizie poddano działającą instalację klienta, nie materiały marketingowe.

> **Skąd dostęp.** Softra FLOTA jest zainstalowana jako program, z którego korzysta G-Rental. Właściciel projektu ma upoważnienie i dostępy do tego programu właśnie w celu zaprojektowania lepszego rozwiązania. Granica z rozdziału wyżej obowiązuje mimo to: korzystamy z interfejsu, konfiguracji, raportów i arkuszy importu/eksportu, a nie z bazy danych, kodu ani plików wykonywalnych producenta.

### Co pokazała instalacja

| Element | Stan |
| --- | --- |
| Klient | aplikacja desktopowa Windows, osobny moduł importu |
| Baza | serwer Firebird/InterBase w sieci lokalnej |
| Raporty | FastReport, szablony na dysku stacji roboczej |
| Aktualizacje | udział sieciowy |
| Konfiguracja | pliki `.ini` **per stacja robocza** — 121 sekcji kartotek |
| Wymiana danych | 30 szablonów Excel |
| Kartoteka pojazdu | siatka „Raport pojazdów" ma **478 kolumn** |

### Kartoteki odczytane z konfiguracji

Pełna lista sekcji daje mapę funkcji systemu flotowego. Najważniejsze grupy:

- **Flota:** pojazdy, marki, liczniki, opony, szkody, polisy, umowy pojazdów, karty drogowe, przypomnienia, autoryzacje napraw, pojazdy zastępcze.
- **Rent:** cenniki, zamówienia, rejestr faktur, należności, kaucje, grupy rabatowe, zlecenia, statusy pojazdów wynajmowanych.
- **Organizacja:** MPK, obiekty kontrolingowe, struktura firmy, jednostki, grupy kosztów, kursy walut.
- **Ludzie:** pracownicy, przydziały, wyposażenie, uprawnienia, nieobecności, wykroczenia, historia zatrudnienia.
- **Finanse:** koszty, rachunki, faktury, budżety i plany, import/eksport do księgowości.

### Szablony importu — bezpośrednia ścieżka migracji

30 arkuszy, które są jednocześnie **dokumentacją struktury danych i drogą migracji**:

```
!Auta, !Dostawcy, !Karty paliwowe, !Klienci, !Kontrakty, !Koszty,
!Mandaty, !Opony, !Polisy, !Przebiegi, !Szkody, !Umowy z dostawcami,
SŁOWNIK_STRUKTURA_FIRMY, SŁOWNIK_MPK, SŁOWNIK_PRACOWNICY,
SŁOWNIK_MARKI_POJAZDÓW, DANE_KOMPLETNE_POJAZDY, Autoryzacje,
Cenniki moduł Rent, Firmy_dostawcy, Harmonogramy_w_umowach_leasingowych,
Karty_paliwowe, Mandaty i wykroczenia, Nieobecności, Obiekty_kontrolingowe,
Opony, Sprzęt pracowników (wydanie/przydział), Stany_liczników,
Szkody, Umowy_z_dostawcami, Uprawnienia pracowników, Wyposażenie i telefony
```

### Raporty warte odtworzenia

Nazwy szablonów raportów z instalacji mówią, czego użytkownicy faktycznie potrzebują:

- raport pojazdów (dane pojazdów, marek, pracowników),
- rozliczenie limitów na kartach paliwowych,
- rozliczenie ryczałtów za kilometry prywatne — w dwóch wariantach: z podsumowaniem na pracownika i z rozbiciem na pojazdy,
- zestawienie kończących się ubezpieczeń,
- kontrola nadprzebiegu z umów z dostawcami,
- opony na pojazdach i przebiegi opon,
- eksport rejestru kosztów do księgowości,
- raport uprawnień operatorów.

### Co przejmujemy, a czego nie

| Przejmujemy | Nie przejmujemy |
| --- | --- |
| zakres rejestrów i ich pola | architektury klient–serwer z instalacją na stacji |
| listę raportów startowych | konfiguracji widoków w plikach na stacji |
| strukturę arkuszy importu (ścieżka migracji) | obsługi drukarki fiskalnej |
| protokoły wydania i zdania | wydruku papierowego jako podstawowej formy protokołu |

> **478 kolumn to nie jest lista do odtworzenia.** To dowód, że kartoteka pojazdu musi być **rozszerzalna przez użytkownika** — inaczej po roku eksploatacji zabraknie miejsca na kolejne pole. Odtwarzamy pola faktycznie wypełnione w danych; reszta idzie do pól rozszerzalnych na żądanie.
>
> Konfiguracja widoków per stacja robocza rodzi typowy objaw: „u mnie ta kolumna jest, u ciebie nie ma". W FleetCore definicja widoku żyje w bazie, przypisana do użytkownika i najemcy.

---

## 2. PasCom II

Producent z Gdyni (oddział pod Poznaniem), trzy produkty: **Flota II**, **Transport II**, **Spedycja II**, plus aplikacja mobilna **nWEB II** i moduł **KSeF**. Wersje językowe: polska, angielska, rosyjska, czeska, niemiecka.

### Ustalenie, które zmienia obraz: PasCom Flota II to pełny system flotowy

Wbrew pierwszemu wrażeniu PasCom nie jest wyłącznie systemem transportowym. **Flota II ma 22 moduły podstawowe i 25 dodatkowych**, pokrywając zakres bardzo zbliżony do Softry:

**Podstawowe:** Zasoby (pojazdy, sprzęt, karty paliwowe), Obsługa Serwisowa i Autoryzacji Napraw, Wyposażenie Fabryczne i Dodatkowe, Ubezpieczenia/Polisy/Szkody, Rozliczenia Okresowe, Ogumienie, Limity, Dokumenty Kosztowe, Import Faktur, Import Zapłat, Faktura KSeF, Kontrahenci-CRM, Dokumenty Kontrahenta, Umowy, Pisma, Pracownicy, Elektroniczna Lista Obecności, Urlopy i Absencje, Import Danych, Załączniki, Harmonogramy, Zestawienia.

**Dodatkowe:** Automatyzacja KSeF, Karty Drogowe i Karty Pracy Sprzętu, Wypożyczalnia, Reklamacje i Niezgodności, Rozliczenia Kierowców, Delegacje i Zaliczki, Środki Trwałe, Komunikator, Parkingi, Telefony, Integracja GPS, nWEB II, Dokumenty Przychodowe, Fakturowanie, Rozrachunki–Eksport Przelewów, **Eksport Danych do FK**, **JPK**, Windykacja, Automatyczne Wiadomości E-mail, Obieg Dokumentów, HR–Szkolenia, Import Cykliczny, **Firmy Zależne**, Tłumaczenia.

**To jest potwierdzenie zakresu z drugiego, niezależnego źródła.** Dwóch producentów niezależnie od siebie uznało ten sam zestaw rejestrów za rdzeń systemu flotowego — mocniejsza przesłanka niż pojedyncza instalacja.

### Transport II

Moduły podstawowe: Zlecenia Transportowe, Kartoteki Transportowe, Podzlecenia, Rozliczanie Palet, Dokumenty Przewozowe, Listy Przewozowe, Dokumenty OCS i OCP, Fakturowanie, Dokumenty Przychodowe i Kosztowe, Import Zapłat, Faktura KSeF, Kontrahenci-CRM, Umowy, Pisma, Pracownicy, Elektroniczna Lista Obecności, Import Danych, Załączniki, Zestawienia.

Dodatkowe warte uwagi: Optymalizacja Zleceń i Pojazdów, Transport Kontenerów, Spedycja Kolejowa, Ofertowanie, Magazyn, **Giełda**, Reklamacje i Niezgodności, Mapy, Windykacja.

Dokumenty generowane: oferty, zlecenia i potwierdzenia transportowe, międzynarodowe listy przewozowe CMR, kontenerowe listy przewozowe, faktury przychodowe i kosztowe.

### Spedycja II — granica, przy której rekomendacja się odwraca

Moduły: Teczka Spedycyjna, Spedycja Lotnicza, Kontenery, Kartoteki Morskie, Regresy i Czynności, **Zgłoszenia Fitosanitarne**, Agencja i Gwarancje Celne, Agencja Statkowa, Skład Celny, Przesyłki.

Dokumenty: zgłoszenia fitosanitarne (WIS, CIS, SANEPID, WIOR, UC), zlecenia manipulacji kontenerów, protokoły zdawczo-odbiorcze, awizacje.

> **Tego nie odtwarzamy.** Agencja celna, skład celny, gwarancje celne i zgłoszenia fitosanitarne to regulowana dziedzina z własnymi procedurami i organami, a nie zestaw formularzy. Budowa bez agenta celnego w zespole jest bezcelowa, nie tylko ryzykowna.
>
> Warunek włączenia z powrotem: firma faktycznie prowadzi działalność spedycyjną **i** ma kogoś, kto te procedury zna.

### Model licencjonowania — wzorzec wart przejęcia

PasCom sprzedaje **moduły podstawowe + dodatkowe + pakiety łączące produkty** (FLOTA+, SPEDYCJA+, Transport+). Pakiet to zestaw modułów jednego produktu udostępniony w drugim.

Rozwiązuje realny problem: klient chcący samą ewidencję pojazdów nie powinien płacić za spedycję kontenerową. W [projekcie bazy](10-database-design.md) odpowiada temu tabela `core.company_modules`.

### nWEB II — aplikacja mobilna

Działa w przeglądarce na smartfonie, tablecie i notebooku. Kierowca zgłasza wykonanie zadania (załadunek, wyładunek, tankowanie), przegląd i badanie techniczne, podaje stan licznika, wysyła skany i zdjęcia. Dyspozytor ma komunikację dwukierunkową.

Deklarowany cel producenta — „eliminowanie pracochłonnej rejestracji wielu dokumentów, np. kart drogowych" — pokrywa się z naszym: stan licznika z telefonu kierowcy jest tańszy i świeższy niż przepisywany z karty drogowej.

**Praca offline nie jest przez producenta udokumentowana.** Dla nas to wymaganie otwarte, patrz [założenia projektu](01-project-brief.md).

### Moduł KSeF

Automatyczna wysyłka faktur sprzedażowych z korektami i zaliczkami, pobieranie dokumentów kosztowych, generowanie XML, pobieranie numerów KSeF i potwierdzeń UPO, automatyczne przypisywanie faktur do zleceń i kontrahentów. Format **FA(3)**.

### Czego nie wiemy

Mimo pełnej listy modułów **nie znamy przepływów pracy** — jak wygląda rejestracja zlecenia, co jest wymagane, gdzie są decyzje. Lista modułów mówi *co*, nie *jak*.

---

## 3. CARMEN (Carmen Software)

Pięć produktów, działających na desktopie, w przeglądarce i mobilnie:

| Produkt | Zakres |
| --- | --- |
| **CARMEN** | ewidencja, historia użytkowania, protokoły, umowy leasingu i wynajmu, polisy, szkody, koszty, importy faktur, **rozliczanie VAT i KUP**, oświadczenia, szkolenia, raporty i analizy floty |
| **CARMEN SaaS** | to samo w modelu chmurowym |
| **PHONEMAN** | telefony i urządzenia mobilne: ewidencja, protokoły, oświadczenia, **import faktur billingowych**, koszty, dekrety, przekazania numerów |
| **MiniCAR GPS** | ewidencja, przekazania i oględziny, protokoły, koszty, liczniki, polisy, szkody, mandaty, terminy, **monitoring pojazdów, rozliczanie jazd prywatnych**, planowanie wyjazdów |
| **Parking Sharing** | zarządzanie miejscami parkingowymi i optymalizacja wykorzystania |

Deklarowana skala: floty od kilkudziesięciu do kilku tysięcy pojazdów.

### Co wnosi ponad Softrę

Trzy rzeczy, których nie widać w instalacji Softry:

1. **Rozliczanie VAT i KUP wprost w systemie flotowym** — potwierdza, że granica między flotą a księgowością powinna przebiegać dalej, niż zwykle się zakłada.
2. **Oświadczenia** jako osobny byt — oświadczenia o używaniu pojazdu do celów służbowych, zgody, potwierdzenia zapoznania z regulaminem.
3. **Oględziny pojazdu** obok protokołu przekazania — to dwie różne czynności.

PHONEMAN potwierdza zaś, że moduł zasobów pracowniczych (telefony, sprzęt) jest w tej dziedzinie standardem, a nie dodatkiem.

---

## 4. TaxOrder Pro — nasz system

Działający system produkcyjny obsługujący 217 pojazdów w 6 spółkach. **To jedyne źródło, z którego przenosimy kod, a nie tylko wymagania.**

### Architektura obecna

Cloudflare Pages (SPA) + Worker (backend REST) + D1 (SQLite) + R2 (pliki) + KV. Frontend w czystym JavaScript, bez frameworka.

To architektura, z której FleetCore rezygnuje na rzecz PostgreSQL i NestJS — uzasadnienie w [architekturze](03-architecture-and-stack.md). Nie znaczy to, że jest zła; znaczy, że nie skaluje się na zakres finansowo-księgowy.

### Co przenosimy bez przepisywania

| Element | Stan | Dlaczego warto |
| --- | --- | --- |
| **Silnik DT-1** | kategorie, progi, zwolnienia dla pojazdów specjalnych | zgodność z bazą produkcyjną **0,24%**, różnice wyjaśnione brakami danych, nie błędem silnika |
| **Stawki gminne** | zweryfikowane **45/45** z uchwałą rady miasta | odczytane z PDF-a uchwały, nie przepisane z drugiej ręki |
| **Usługa OCR** | parser geometryczny dowodów, korekcja orientacji strony | 8–11 s/dokument; dopasowanie etykieta→wartość po współrzędnych, nie regex |
| **Dekodowanie Aztec** | pełna ścieżka obraz → bajty → pola | 17/17 pól, dane z pewnością 100% |
| **Importy** | karty paliwowe, telematyka, zestawienia | działają na realnych danych |
| **Scalanie źródeł z rangami** | 907 pojazdów z 4 źródeł | rozstrzyganie konfliktów opisane w [modelu danych](05-data-model-and-analytics.md) |
| **Bramki testowe** | ~19 plików, 154 asercje, ~20 s bez sieci | każda chroni przed konkretnym, zdarzonym błędem |

### Czego NIE przenosimy — i to jest ważniejsze

| Element | Powód |
| --- | --- |
| **Integracja KSeF** | celuje w API, które **już nie istnieje** — host zwraca stronę portalu, nie API; ścieżka pochodzi z KSeF 1.0. Napisać od nowa wg `open-api.json` Ministerstwa Finansów |
| **Pobieranie z otwartego API CEPiK po numerze rejestracyjnym** | **filtr nie działa** — zwraca pierwszy rekord z zakresu dat niezależnie od numeru. Szczegóły w [integracjach](04-api-integrations.md) |
| **Baza D1/SQLite** | brak transakcji wielotabelowych, partycjonowania i RLS potrzebnych w module finansowym |
| **Frontend bez frameworka** | ~9700 linii w jednym pliku; nie skaluje się na 7 modułów |

### Zmierzone pułapki — najcenniejszy wkład tego systemu

To nie są anegdoty. Każda pozycja kosztowała czas i jest udokumentowana w odpowiednim dokumencie:

| Pułapka | Objaw | Gdzie opisana |
| --- | --- | --- |
| Filtr API ignorowany zamiast odrzucony | poprawnie wyglądający rekord innego pojazdu | [integracje](04-api-integrations.md) |
| Odwrócona orientacja strony w OCR | wartość z sąsiedniej rubryki, w dopuszczalnym zakresie | [integracje](04-api-integrations.md) |
| Dwie kopie tablicy stałych | rozjazd nie tylko ze sobą, ale i z danymi | [model danych](05-data-model-and-analytics.md) |
| Wartość domyślna pola podatkowego | deklaracja z zaniżoną stawką, wygląda poprawnie | [model danych](05-data-model-and-analytics.md) |
| Zero traktowane jako wartość, nie brak danych | 28 z 43 fałszywych konfliktów | [model danych](05-data-model-and-analytics.md) |
| Glob migracji łapiący pliki wycofujące | tabele kasowane co noc, kod wyjścia sukces | [wdrożenie](08-cluster-deployment.md) |
| Cicha kaskada OCR | awaria warstwy = gorsze dane, nie błąd | [architektura](03-architecture-and-stack.md) |
| Izolacja najemców w kodzie, nie w bazie | 4 podatności IDOR na pobieraniu pojedynczego rekordu | [bezpieczeństwo](06-security-privacy-compliance.md) |
| Kod generowany jako tekst | niewidoczny dla wszystkich narzędzi audytu | [bezpieczeństwo](06-security-privacy-compliance.md) |

---

## 5. Systemy, na których firma pracuje dziś: ZSI i MyCar

Nie są systemami odniesienia — nie odtwarzamy ich funkcji. Są **źródłami danych** dla migracji i, w przypadku ZSI, **systemem docelowym** dla księgowania. Każdy przyszły klient będzie miał swój odpowiednik; dlatego integracje projektujemy jako porty z konfiguracją per najemca, a ZSI i MyCar są pierwszymi implementacjami.

### ZSI — ERP firmy

| Element | Stan wiedzy |
| --- | --- |
| Rola | ERP firmy: księgowość, kartoteki, w tym pojazdy i kierowcy |
| Baza | SQL Server, baza `mToilet_Produkcyjna` na serwerze `SRVDRI` |
| Co wnosi do floty | **norma EURO** (dowód rejestracyjny nie ma na nią rubryki), przebiegi, kierowca, OC/AC |
| Jakość | nieznane DMC zapisane jako `0` (30 ze 181 wierszy); przypadki, w których ZSI ma rację, a OCR dowodu się myli (marka „LONDAIS" zamiast Iveco ML75E16, 7,5 t) |
| Ranga w scalaniu | 3 ([model danych](05-data-model-and-analytics.md)) |
| Istniejąca integracja | skrypt `tools/zsia-sync.ps1` w TaxOrder Pro: odczyt pojazdów i kierowców z bazy, eksport do JSON — materiał poglądowy (jakie pola i skąd), **nie wzorzec integracji** |
| Analiza | wykonana na komputerze **MT0268**; materiały źródłowe (m.in. `Dokumentacja pojazdów/Pulpit/Brak VIN w ZSI.xlsx`) są na tym komputerze — **do przekazania Rafałowi** |

Dwa kierunki integracji:

1. **ZSI → FleetCore** — pojazdy, kierowcy, norma EURO, przebiegi; przy migracji i okresowo.
2. **FleetCore → ZSI** — dekrety i dokumenty kosztowe do zaksięgowania. Granica odpowiedzialności z ADR-014 TaxOrder Pro zostaje: FleetCore jest źródłem prawdy kosztu operacyjnego przed księgowaniem, ERP — dokumentu zaksięgowanego, rozrachunku i płatności. Cykl `ready_for_export → exported → accepted_by_erp → posted`; brak odpowiedzi ERP nie oznacza sukcesu.

> **Decyzja właściciela (10.10.2026): integracja z ZSI na razie wyłącznie przez eksport plików**, w obu kierunkach. API ZSI — temat na później. Bez odczytu bazy ZSI i bez zapisu do niej; dokumenty do księgowania wyłącznie przez mechanizm importu ZSI. Szczegóły: [platforma integracji](16-platforma-integracji.md).

### MyCar — platforma flotowa

| Element | Stan wiedzy |
| --- | --- |
| Co wnosi | karta paliwowa, polisa, GPS, e-TOLL, leasing |
| Format | eksport XLS, który w rzeczywistości jest **TSV w UTF-16LE** — importer musi rozpoznać kodowanie, nie ufać rozszerzeniu |
| Ranga w scalaniu | 2 |

### ORLEN Flota — karty paliwowe

Eksport CSV: numery kart, ważność, status, blokady. Ranga 1. Schemat importu kart opisany w [integracjach](04-api-integrations.md).

---

## Zestawienie: co który system wnosi do zakresu

| Obszar | Softra | PasCom | CARMEN | TaxOrder Pro |
| --- | --- | --- | --- | --- |
| Kartoteka pojazdu | ●●● | ●●● | ●● | ●● |
| Polisy, szkody | ●●● | ●● | ●● | ● |
| Opony | ●●● | ●● | — | — |
| Karty paliwowe | ●●● | ●● | — | ●●● |
| Rent / CFM | ●●● | ●● | — | — |
| Transport | — | ●●● | — | — |
| Spedycja | — | ●●● | — | — |
| Telefony, wyposażenie | ●● | ●● | ●●● | — |
| Telematyka GPS | — | ●● | ●●● | ●● |
| VAT, dekretacja, FK | ●● | ●●● | ●● | ● |
| KSeF, JPK | — | ●●● | — | ◐ |
| **Podatek DT-1** | — | — | — | **●●●** |
| **Opłata środowiskowa, CO2** | — | — | — | **●●** |

● = zakres potwierdzony · ◐ = obecne, ale wadliwe · — = brak

**Ostatnie dwa wiersze to przewaga produktu.** Żaden z systemów odniesienia nie liczy podatku od środków transportowych ani opłaty środowiskowej. To nie jest luka do wypełnienia dla porządku — to jedyny obszar, w którym FleetCore robi coś, czego konkurencja nie robi wcale.
