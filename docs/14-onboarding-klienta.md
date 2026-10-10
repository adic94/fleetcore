# Onboarding nowego klienta

Jak klient przechodzi od pierwszej rozmowy do pracy na produkcji. Dokument obowiązuje od pierwszego klienta zewnętrznego — własna flota przechodzi tę samą ścieżkę jako klient zerowy.

## Zasada

Onboarding to **migracja danych z twardym kryterium odbioru**, nie instalacja programu. To samo kryterium co w fazie 1 ([roadmapa](07-roadmap.md)), stosowane u każdego klienta: liczba pojazdów, suma kosztów i liczba rekordów w każdym rejestrze zgadzają się ze źródłem, a podatek DT-1 policzony przez FleetCore jest porównany z ostatnią deklaracją klienta i każda różnica jest wyjaśniona.

Podział na dwa momenty:

| Kiedy | Co | Dane klienta | Podstawa |
| --- | --- | --- | --- |
| **Przed umową** | **Demo** — przykładowa flota albo lista pojazdów klienta, z szybkim testem podatkowym | wyłącznie dane pojazdów, **bez danych osobowych** | regulamin demo akceptowany przy rejestracji |
| **Po umowie** | **Audyt danych** jako pierwszy etap wdrożenia — pełny import, raport jakości, potwierdzenie terminu i ceny | pełny eksport, w tym dane osobowe | umowa wdrożeniowa + umowa powierzenia |

Powody takiego podziału:

- przed umową nie przetwarzamy danych osobowych klienta — nie potrzeba umowy powierzenia, zanim klient cokolwiek kupi;
- klient i tak widzi wartość produktu na **własnych pojazdach**: szybki test podatkowy w demo pokazuje braki i ryzyko zaniżonej stawki na jego liście;
- pełny audyt to realna praca wdrożeniowca, więc odbywa się w ramach umowy, a nie za darmo dla każdego, kto porównuje oferty;
- **termin i cena wdrożenia są potwierdzane po audycie**, nie przed nim — jakość danych to ryzyko nr 1 każdego harmonogramu ([roadmapa](07-roadmap.md)).

---

## Etapy

| # | Etap | Kto | Czas | Wynik |
| --- | --- | --- | --- | --- |
| 0 | Kwalifikacja | my + klient | 1 spotkanie | ankieta, dostęp do demo |
| 1 | Demo | klient (samodzielnie) + my | do 30 dni | szybki test podatkowy na liście pojazdów klienta |
| 2 | Umowa wdrożeniowa | klient + my | wg klienta | umowa z etapem audytu, umowa powierzenia, moduły |
| 3 | Założenie najemcy w trybie wdrożenia | my | 1 dzień | najemca klienta w statusie `onboarding` |
| 4 | Audyt danych | my | 1–2 tygodnie | **raport jakości danych**; potwierdzony termin i cena |
| 5 | Uzupełnienie braków | klient | wg skali braków | lista „do rozstrzygnięcia" zamknięta |
| 6 | Import końcowy i odbiór liczb | my + klient | kilka dni | protokół odbioru danych; najemca w statusie `active` |
| 7 | Konfiguracja | my + administrator klienta | kilka dni | gotowe środowisko |
| 8 | Szkolenia per rola | my | 1–3 dni | przeszkoleni użytkownicy |
| 9 | Praca równoległa | klient | 1 cykl rozliczeniowy | potwierdzenie zgodności liczb |
| 10 | Start i opieka | my | 30 dni | klient na produkcji, stary system do wyłączenia |

### 0. Kwalifikacja

Ankieta, wypełniana na spotkaniu:

- liczba pojazdów, spółek i oddziałów;
- obecne systemy: flotowy, księgowy, arkusze — i **czy umowa z obecnym dostawcą pozwala wydać dane**, w jakim formacie i w jakim terminie;
- okres wypowiedzenia obecnych umów — wyznacza najwcześniejszą datę wyłączenia starego systemu;
- potrzebne moduły: Flota, Podatki, Finanse, Zasoby, Telematyka, Rent, Transport;
- dostawcy kart paliwowych, system telematyczny, użycie KSeF;
- kto po stronie klienta jest decydentem zakresu, a kto ma wiedzę o flocie (fleet manager, księgowa).

**Wynik:** konto demo dla klienta i szablon listy pojazdów.

### 1. Demo

Osobne środowisko `demo` (patrz niżej). Klient dostaje konto z dwiema możliwościami:

1. **Przykładowa flota** — gotowy zestaw syntetycznych pojazdów, zdarzeń i dokumentów pokazujący wszystkie moduły.
2. **Lista własnych pojazdów** — klient wgrywa szablon z danymi pojazdów:

| Kolumna | Wymagana | Po co |
| --- | --- | --- |
| VIN | tak | wykrywanie duplikatów — **zapisywany wyłącznie jako skrót**, patrz niżej |
| Numer rejestracyjny | nie | **nie jest zapisywany**; pokazujemy tylko 3 ostatnie znaki, żeby klient rozpoznał pojazd |
| Rodzaj pojazdu | tak | kategoria podatkowa |
| DMC, DMC zespołu | tak | kategoria podatkowa |
| Liczba osi, rodzaj zawieszenia | od 12 t | stawka DT-1 |
| Liczba miejsc | autobusy | stawka DT-1 |
| Gmina siedziby (TERYT lub nazwa) | tak | właściwa uchwała ze stawkami |
| Kwota z ostatniej deklaracji per pojazd | nie | porównanie z naszym wyliczeniem |

**Szablon nie ma kolumn osobowych, a import w demo je odrzuca** — kolumna rozpoznana jako imię, nazwisko, PESEL, adres czy telefon nie jest wczytywana, a klient dostaje komunikat dlaczego.

**Demo nie przechowuje identyfikatorów pojazdu.** Import zamienia VIN na skrót kryptograficzny z losową solą właściwą dla danego konta demo (wystarcza do wykrycia duplikatów, nie da się z niego odtworzyć VIN-u ani porównać z innym kontem), a z numeru rejestracyjnego zapisuje najwyżej 3 ostatnie znaki. Pełne wartości istnieją tylko w pamięci procesu importu. Szybki test podatkowy ich nie potrzebuje — liczy z masy, osi, zawieszenia, rodzaju i gminy.

Na liście pojazdów demo automatycznie pokazuje **szybki test podatkowy**:

- pojazdy, dla których nie da się wyliczyć DT-1, i których pól brakuje (braki blokujące, nie formalne);
- pojazdy, dla których nasze wyliczenie różni się od kwoty podanej przez klienta, z przyczyną;
- duplikaty VIN pod różnymi numerami rejestracyjnymi;
- pola wypełnione hurtem jedną wartością.

To jest najkrótsza droga do pokazania głównej przewagi produktu — bez umowy, bez danych osobowych, bez pracy wdrożeniowca.

> **Dlaczego bez identyfikatorów.** Dane pojazdów spółki nie są danymi osobowymi, ale u przedsiębiorcy prowadzącego jednoosobową działalność VIN i numer rejestracyjny mogą identyfikować osobę. Zamiast osobnej ścieżki dla takich klientów demo nie przechowuje tych identyfikatorów od nikogo — reguła jest jedna i nie zależy od deklaracji klienta. Do potwierdzenia z prawnikiem, że skrót z solą per konto i 3 znaki tablicy wystarczają, żeby demo pozostało poza zakresem danych osobowych.

### 2. Umowa wdrożeniowa

- umowa licencyjna / świadczenia usługi, regulamin, polityka prywatności;
- **umowa powierzenia przetwarzania danych osobowych**, podpisana przed przekazaniem pełnego eksportu, określająca co najmniej:
  - cel i czas przetwarzania (świadczenie usługi przez czas trwania umowy);
  - kategorie danych (dane pojazdów, imiona i nazwiska użytkowników pojazdów i kierowców, numery kart paliwowych, dane lokalizacyjne przy module Telematyka) i kategorie osób (pracownicy i współpracownicy klienta);
  - przetwarzanie wyłącznie na udokumentowane polecenie klienta;
  - środki bezpieczeństwa ([bezpieczeństwo](06-security-privacy-compliance.md));
  - podmioty przetwarzające dalej (dostawca chmury, magazyn obiektowy) — z nazwy;
  - pomoc przy żądaniach osób, których dane dotyczą, i zgłaszanie incydentów bez zbędnej zwłoki;
  - usunięcie albo zwrot danych po zakończeniu umowy (patrz „Odejście klienta");
- **audyt danych jako pierwszy, osobno wyceniony etap umowy**, z dwiema zasadami:
  - termin startu i cena wdrożenia są **potwierdzane aneksem po raporcie z audytu** — przed audytem podajemy widełki;
  - klient może **odstąpić po audycie**, płacąc wyłącznie za audyt; wtedy dane są usuwane z protokołem, a raport zostaje u klienta;
- jeśli klient ma telematykę: przypomnienie o **regulaminie monitoringu i informacji dla pracowników** — wymóg kodeksu pracy po stronie klienta, warunek włączenia modułu Telematyka;
- moduły zapisane w `core.company_modules`.

Wzory umowy, umowy powierzenia i regulaminu demo przygotowuje prawnik raz, przed pierwszym klientem.

### 3. Założenie najemcy w trybie wdrożenia

Wykonuje superadmin, przez dedykowaną funkcję zakładania najemcy:

1. spółki klienta w `core.companies` ze statusem `onboarding`;
2. moduły w `core.company_modules`;
3. pierwszy administrator klienta, z obowiązkowym MFA;
4. nadanie roli `admin` z flagą `is_implementer` dla naszego wdrożeniowca na czas wdrożenia.

Po założeniu **superadmin nie ma dostępu do danych klienta** ([bezpieczeństwo](06-security-privacy-compliance.md)). Test izolacji najemców obejmuje nową spółkę automatycznie.

**Status `onboarding`** pozwala wyczyścić dane importowe najemcy i wczytać je ponownie — tyle razy, ile trzeba w etapach 4–6. Po odbiorze danych status zmienia się na `active` i czyszczenie przestaje być możliwe; dalej obowiązują normalne zasady (usuwanie miękkie, ślad audytowy).

#### Czyszczenie danych importowych — zasady

| | |
| --- | --- |
| **Co jest kasowane** | wszystkie wiersze danych klienta w schematach `fleet`, `tax` (deklaracje i pozycje), `fin`, `rent`, `tms`, `assets`, `telematics`, `integr.outbox`; w `docs` — dokumenty i wyniki OCR **powstałe z importu**, razem z plikami w magazynie obiektowym; w `core` — pracownicy, kontrahenci, adresy, oddziały, MPK |
| **Co zostaje** | spółki, moduły, użytkownicy i nadania, słowniki spółki, definicje pól rozszerzalnych i raportów, zapisane mapowania importu, **pliki źródłowe importu**, **raporty jakości danych (PDF)**, cały `audit.audit_logs` |
| **Kto uruchamia** | użytkownik z rolą `admin` w tej spółce **i** flagą wdrożeniowca na nadaniu; potwierdzenie przez wpisanie kodu spółki |
| **Jak** | jedna funkcja w bazie, wywoływana przez worker na roli `fleetcore_maint`; w **jednej transakcji** blokuje wiersz spółki (`SELECT … FOR UPDATE`), sprawdza `lifecycle = 'onboarding'`, kasuje dane, zapisuje wpis w audycie. Pliki w magazynie kasowane po zatwierdzeniu transakcji, z listy zapisanej w tej transakcji; nieudane kasowanie pliku ponawiane przez zadanie `retention` |
| **Ślad** | wpis `action = 'onboarding_wipe'` w `audit.audit_logs`: kto, kiedy, liczba skasowanych wierszy per tabela i liczba plików |
| **Odtworzenie** | brak cofnięcia — dane odtwarza się ponownym importem z zachowanych plików źródłowych |

Zmiana `onboarding → active` blokuje ten sam wiersz spółki, więc czyszczenie i przejście w `active` nie mogą się wykonać równocześnie. Trigger na `core.companies` **nie pozwala wrócić** z `active` do `onboarding`.

Dzięki temu audyt odbywa się **od razu w docelowym miejscu**: nie ma osobnego środowiska audytowego ani przenoszenia danych między środowiskami.

### 4. Audyt danych

Klient przekazuje pełny eksport ze swojego systemu i — jeśli ma — skany dowodów rejestracyjnych.

1. Import przez kreator z mapowaniem dla systemu źródłowego klienta, do najemcy w statusie `onboarding`.
2. OCR dowodów rejestracyjnych przez kaskadę ([integracje](04-api-integrations.md)).
3. Scalanie źródeł z rangami i pochodzeniem pól ([model danych](05-data-model-and-analytics.md)).
4. Wyliczenie DT-1 na danych klienta i porównanie z jego ostatnią deklaracją.
5. Wygenerowanie raportu.

#### Raport jakości danych — zawartość

| Sekcja | Co pokazuje | Dlaczego klienta to obchodzi |
| --- | --- | --- |
| Podsumowanie | ile pojazdów, rekordów i dokumentów wczytano, ile odrzucono i dlaczego | czy dane w ogóle nadają się do migracji |
| **Ryzyko podatkowe** | pojazdy z brakami blokującymi wyliczenie DT-1; pojazdy, dla których nasze wyliczenie różni się od deklaracji klienta, z przyczyną (np. brak liczby osi lub zawieszenia powyżej 12 t) | **zaniżona deklaracja to ryzyko zaległości z odsetkami; zawyżona to nadpłata** |
| Duplikaty | ten sam VIN pod kilkoma numerami rejestracyjnymi; rekordy, które wyglądają na dwa pojazdy, a są jednym | zawyżone koszty i podatek, błędna liczba pojazdów |
| Dane podejrzane | pola wypełnione hurtem jedną wartością; rekordy wewnętrznie sprzeczne (kategoria M1 przy DMC powyżej 3,5 t, model równy statusowi itp.) | dane „kompletne", które są błędne |
| Konflikty źródeł | pola, w których źródła tej samej rangi podają różne wartości | co trzeba rozstrzygnąć z dokumentem w ręku |
| Kompletność | braki formalne vs **braki blokujące**, osobno | które braki kosztują pieniądze, a które są porządkowe |
| Plan uzupełnienia | lista braków posortowana od najdroższych, z szacunkiem pracy po stronie klienta | ile pracy czeka klienta przed startem |

Raport **nie zawiera** rekomendacji podatkowych ani ocen prawnych — wskazuje rozbieżności i ich przyczynę. Decyzję o korekcie deklaracji klient podejmuje ze swoim doradcą.

**Wynik:** raport w PDF, omówiony z klientem; aneks z potwierdzonym terminem startu i ceną wdrożenia — albo odstąpienie klienta po audycie.

### 5. Uzupełnienie braków

Praca klienta z dokumentem w ręku, na ekranie „Rekordy do rozstrzygnięcia" ([opis produktu](02-product-functional-spec.md)). Kolejność: najpierw braki blokujące podatek, od najdroższych, potem pozostałe.

**Nie zniknie przez zmianę systemu** i jest zwykle najdłuższym etapem — dlatego jej skalę zna się z audytu, przed potwierdzeniem terminu.

### 6. Import końcowy i odbiór liczb

Wdrożeniowiec czyści dane importowe najemcy i wczytuje je ponownie: te same pliki źródłowe, to samo mapowanie, plus uzupełnienia klienta. Raport importu końcowego porównywany jest z raportem audytu: liczba wczytanych rekordów per rejestr = audyt + uzupełnienia − świadomie odrzucone.

Kryterium odbioru, sprawdzane przy kliencie i zapisane w protokole:

- liczba pojazdów zgodna ze źródłem (z wyjaśnieniem scalonych duplikatów);
- suma kosztów w każdym rejestrze zgodna ze źródłem;
- liczba rekordów w każdym rejestrze zgodna ze źródłem;
- DT-1 porównany z ostatnią deklaracją, każda różnica wyjaśniona;
- lista „do rozstrzygnięcia" pusta albo każda pozycja świadomie zaakceptowana przez klienta.

Po podpisaniu protokołu status najemcy zmienia się na `active`. Pliki źródłowe importu są usuwane z magazynu po 30 dniach od odbioru, z wpisem w śladzie audytowym.

### 7. Konfiguracja

- MPK, oddziały, słowniki;
- pola rozszerzalne — **tylko pola faktycznie wypełnione w danych klienta**, na podstawie audytu, nie na podstawie listy życzeń;
- raporty startowe i widoki siatek;
- użytkownicy, role, nadania spółek;
- schematy importu kart paliwowych dla dostawców klienta;
- telematyka (jeśli moduł włączony), tokeny KSeF per spółka.

### 8. Szkolenia

Osobno dla każdej roli, na danych klienta, nie na danych demonstracyjnych:

| Rola | Zakres |
| --- | --- |
| Fleet manager | kartoteka, rejestry, importy, przypomnienia, rozstrzyganie konfliktów |
| Księgowość | dekretacja, VAT, eksport do FK, KSeF, DT-1 |
| Administrator | użytkownicy, role, słowniki, pola rozszerzalne |
| Kierowcy | aplikacja mobilna: protokoły, licznik, szkody — krótka instrukcja + nagranie |

### 9. Praca równoległa

Jeden pełny cykl rozliczeniowy (zwykle miesiąc) w obu systemach. Na koniec porównanie: koszty, dekrety, stany liczników. Rozbieżność jest wyjaśniana przed wyłączeniem starego systemu, nie po.

### 10. Start i opieka

- 30 dni opieki powdrożeniowej z kontaktem do wdrożeniowca;
- odebranie wdrożeniowcowi nadania do spółki klienta po zakończeniu opieki;
- wyłączenie starego systemu zgodnie z okresem wypowiedzenia ustalonym w etapie 0.

---

## Ścieżki migracji wg systemu źródłowego

| Źródło | Stan mapowania | Uwagi |
| --- | --- | --- |
| Softra FLOTA | **gotowe** — 30 arkuszy importu ([systemy odniesienia](12-source-systems.md)) | najszybsza ścieżka |
| PasCom Flota II | do zbudowania przy pierwszym kliencie | potem w bibliotece mapowań |
| CARMEN | do zbudowania przy pierwszym kliencie | potem w bibliotece mapowań |
| Inny system | do zbudowania przy pierwszym kliencie | jw. |
| Excel / brak systemu | **nasz szablon importu** z opisem kolumn | klient wypełnia szablon |

Mapowanie budujemy **raz na system źródłowy**, nie raz na klienta. Każdy kolejny klient z tego samego systemu wdraża się szybciej — biblioteka mapowań to przewaga, która rośnie z każdym wdrożeniem.

Zasady z [systemów odniesienia](12-source-systems.md) obowiązują także tu: migracja wyłącznie z eksportów udostępnianych klientowi przez producenta, nigdy bezpośrednio z bazy cudzego systemu.

---

## Środowisko demo

Osobne środowisko `demo`, odizolowane od produkcji — inna baza, inny magazyn plików, inne poświadczenia:

- każdy klient demo to osobny najemca; przykładowa flota jest kopiowana do niego przy założeniu konta;
- rejestracja wymaga akceptacji **regulaminu demo**: tylko pojazdy firmowe, żadnych danych osobowych, usunięcie po 30 dniach;
- **import demo przyjmuje tylko szablon listy pojazdów** i odrzuca kolumny osobowe; nie ma tu importu kosztów, kart paliwowych ani dokumentów;
- moduły w demo są włączone wszystkie, ale **eksport danych jest wyłączony** — demo pokazuje, nie zastępuje systemu;
- **usuwanie automatyczne**: najemca demo jest usuwany 30 dni po założeniu (z możliwością jednorazowego przedłużenia przez nas), bez kopii zapasowych dłuższych niż 7 dni;
- te same bramki bezpieczeństwa co na produkcji: RLS, test izolacji, szyfrowanie, ślad audytowy.

Dane z demo **nie przechodzą** na produkcję. Lista pojazdów wgrana w demo to próbka; na produkcję wchodzi pełny eksport w etapie 4.

---

## Odejście klienta

Symetrycznie do wejścia — klient musi wiedzieć przed podpisaniem umowy, jak odejdzie:

- **pełny eksport danych** w formatach otwartych (CSV/XLSX + dokumenty z magazynu obiektowego), w tym historia zdarzeń, deklaracje i ślad audytowy;
- termin na pobranie eksportu, potem usunięcie danych z protokołem;
- kopie zapasowe zawierające dane klienta wygasają w normalnym cyklu retencji kopii — okres zapisany w umowie powierzenia;
- obowiązek przechowywania dokumentów księgowych przez 5 lat ([bezpieczeństwo](06-security-privacy-compliance.md)) spoczywa na kliencie jako administratorze danych — dlatego eksport musi obejmować dokumenty, nie tylko tabele.

Odstąpienie po audycie (etap 4) to ten sam proces w skróconej formie: raport zostaje u klienta, dane najemcy są usuwane z protokołem.

---

## Orientacyjne czasy

Szacunek do weryfikacji na pierwszych wdrożeniach, nie zobowiązanie:

| Klient | Od podpisania umowy do startu |
| --- | --- |
| Mała flota z Excela, do 100 pojazdów | 2–3 tygodnie |
| Średnia flota z systemu z gotowym mapowaniem | 4–6 tygodni |
| Średnia flota z systemu bez mapowania | 6–8 tygodni |

Największą zmienną jest etap 5 — praca klienta przy uzupełnianiu braków. Dlatego termin potwierdzamy po audycie, a nie w umowie.

---

## Wymagania dla produktu wynikające z onboardingu

Do backlogu ([roadmapa](07-roadmap.md)):

1. **Kreator importu z biblioteką mapowań** per system źródłowy, z podglądem i raportem odrzuceń.
2. **Środowisko demo** z przykładową flotą, importem listy pojazdów odrzucającym kolumny osobowe, szybkim testem podatkowym i automatycznym usuwaniem.
3. **Status najemcy `onboarding` / `active`** z funkcją czyszczenia danych importowych dostępną wyłącznie w statusie `onboarding`.
4. **Raport jakości danych w PDF**, generowany z danych importu.
5. **Funkcja zakładania najemcy** dla superadmina, bez późniejszego dostępu do danych.
6. **Pełny eksport danych klienta** przy odejściu i przy odstąpieniu po audycie.
7. **Szablony importu**: lista pojazdów dla demo i pełny szablon dla klientów bez systemu, z opisem kolumn.

Rola po naszej stronie: **wdrożeniowiec** ([zasoby](13-resources-and-prerequisites.md)).

### Na później: demo samoobsługowe na szerszą skalę

Rejestracja do demo bez spotkania (etap 0 pomijany), z szybkim testem podatkowym jako głównym magnesem. Ma sens dopiero, gdy import listy pojazdów jest dopracowany na kilku klientach i ruch z demo zaczyna obciążać wdrożeniowców. Do tego czasu dostęp do demo daje się po kwalifikacji.
