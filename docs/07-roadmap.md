# Plan działania i roadmapa

## Zasada: każda faza kończy się czymś działającym

Faza, po której nie da się wykonać żadnej pełnej czynności użytkownika, jest fazą przegraną — nawet jeśli powstał w niej poprawny kod. Dlatego każda ma zdefiniowane **kryterium ukończenia**: co konkretnie użytkownik potrafi zrobić od początku do końca.

Szacunki zakładają zespół 3–4 osób, patrz [zasoby](13-resources-and-prerequisites.md).

---

## Faza 0 — fundament (2–3 osobomiesiące)

Nie ma wartości dla użytkownika i to jest w porządku — to jedyna taka faza.

Zakres:

- Szkielet repozytorium, środowiska deweloperskie i CI.
- Schemat `core`: najemcy, użytkownicy, uprawnienia, dostępy do spółek, słowniki.
- **Polityki RLS i test izolacji najemców jako bramka CI** — od pierwszego dnia, nie później.
- Uwierzytelnianie, sesje, ślad audytowy.
- Warstwa dokumentów: magazyn obiektowy, wgrywanie, deduplikacja po sumie kontrolnej.

**Kryterium ukończenia:** administrator zakłada spółkę i użytkownika, użytkownik loguje się i wgrywa dokument, a próba sięgnięcia po dane innej spółki kończy się odmową — potwierdzoną testem automatycznym.

> **RLS wchodzi w fazie 0, nie później.** Dokładanie izolacji danych do działającego systemu jest przepisywaniem, nie rozszerzaniem — każde zapytanie napisane wcześniej wymaga przeglądu.

---

## Faza 1 — moduł Flota (8–12 osobomiesięcy)

Rdzeń produktu.

Zakres:

- Kartoteka pojazdu z polami rozszerzalnymi i historią numerów rejestracyjnych.
- Tabela zdarzeń z partycjonowaniem.
- Rejestry: umowy, polisy, szkody, opony, karty paliwowe, liczniki, mandaty, autoryzacje.
- Przypomnienia o terminach — wg daty **i wg przebiegu**.
- Import kart paliwowych i faktur kosztowych.
- Raporty: zestaw startowy z [opisu produktu](02-product-functional-spec.md).
- Migracja danych historycznych przez arkusze importu.
- Pochodzenie pól (`vehicle_field_provenance`) i lista rekordów sprzecznych.

**Kryterium ukończenia:** migracja odtwarza kartotekę bez ręcznych poprawek — liczba pojazdów, suma kosztów i liczba rekordów w każdym rejestrze zgadzają się ze źródłem.

### Ryzyko główne: 478 kolumn

Kartoteka pojazdu w systemie odniesienia ma 478 kolumn w siatce raportu. **Pokusa odtworzenia wszystkich jest silna i zabójcza dla harmonogramu.**

Reguła: odtwarzamy pola **faktycznie wypełnione w danych produkcyjnych**; reszta idzie do pól rozszerzalnych na żądanie. Decyzję o tym, co jest „faktycznie wypełnione", podejmuje się raz, na podstawie zapytania do danych — nie w dyskusji.

---

## Faza 2 — podatki i dekretacja (4–6 osobomiesięcy)

To tutaj produkt zaczyna robić coś, czego nie robi konkurencja.

Zakres:

- Silnik DT-1 przeniesiony z istniejącego systemu, z bramkami testowymi.
- Stawki gminne, deklaracje, korekty, miesiące posiadania.
- Kolumna braków blokujących i raport kompletności danych podatkowych.
- Rejestry VAT zakupu i sprzedaży, proporcja odliczenia 0/50/100%.
- Dekretacja kosztów na MPK i konta, eksport do FK.
- **KSeF napisany od nowa** wg aktualnego kontraktu Ministerstwa Finansów.

**Kryterium ukończenia, twarde i liczbowe:** suma podatku DT-1 policzona przez FleetCore zgadza się **co do złotówki** z niezależnym wyliczeniem na tych samych danych.

Punkt odniesienia: dzisiejsza różnica to 0,24% (552 zł na 229 104 zł), w całości wyjaśniona brakami liczby osi. Po migracji ma wynosić zero — braki uzupełnione albo **jawnie oznaczone jako blokujące**.

> **Opłata środowiskowa nie wchodzi do tej fazy jako gotowa funkcja.** Wymaga klucza trójwymiarowego (paliwo × EURO × klasa pojazdu) oraz osobnego źródła gęstości paliw, którego obwieszczenie ze stawkami nie podaje. Do czasu uzupełnienia obu rzeczy funkcja ma **odmawiać wyliczenia**, a nie szacować.

---

## Faza 3 — Zasoby, telematyka, aplikacja mobilna (4–6 osobomiesięcy)

Trzy mniejsze obszary, które razem domykają codzienną pracę.

- Wyposażenie pracownika, telefony, protokoły wydania i zdania, oświadczenia.
- Integracja telematyczna: pozycje, przebiegi jako źródło liczników, jazdy prywatne.
- Geofency stacji paliw i weryfikacja krzyżowa tankowań.
- Aplikacja mobilna kierowcy: zadania, licznik, zdjęcia, podpis protokołu, zgłoszenie szkody.

**Kryterium ukończenia:** kierowca wydaje i zdaje pojazd na telefonie, a stan licznika trafia do systemu bez przepisywania z papieru.

> **Praca offline rozstrzyga się przed tą fazą, nie w jej trakcie.** Jeśli protokoły mają działać bez zasięgu, architektura klienta mobilnego wygląda inaczej od pierwszej linii kodu.

---

## Faza 4 — Rent / CFM (6–9 osobomiesięcy) — warunkowa

Budowana tylko wtedy, gdy firma prowadzi wynajem.

- Cenniki, grupy rabatowe, rezerwacje, dostępność.
- Zlecenia najmu, kaucje, pojazdy zastępcze.
- Faktury najmu, należności, import wyciągów bankowych i dopasowanie wpłat.
- Miejsca parkingowe.

**Kryterium ukończenia:** pełny cykl od rezerwacji przez wydanie i zwrot po fakturę i zaksięgowanie wpłaty.

---

## Faza 5 — Transport (6–9 osobomiesięcy) — warunkowa

Budowana tylko wtedy, gdy firma prowadzi transport zarobkowy.

- Zlecenia transportowe i podzlecenia, kartoteki transportowe.
- Dokumentacja przewozowa: CMR, listy przewozowe, dokumenty OCS i OCP.
- Rozliczenie kursu z opłatami drogowymi i paletami.
- Ofertowanie, reklamacje, zlecanie przewoźnikom zewnętrznym.

**Nie zaczynać bez warsztatu z dyspozytorem.** Lista modułów systemów odniesienia mówi, *co* obsługują, nie *jak* wygląda rejestracja zlecenia. Agenda warsztatu: przejść listę z [systemów odniesienia](12-source-systems.md) i zaznaczyć, co jest w tej firmie faktycznie używane.

**Kryterium ukończenia:** zlecenie od przyjęcia po rozliczenie kursu i fakturę.

### Czego w tej fazie nie ma

Spedycja morska i lotnicza, Teczka Spedycyjna, Kontenery, Agencja i Skład Celny, Gwarancje Celne, Zgłoszenia Fitosanitarne.

**Warunek włączenia z powrotem:** firma faktycznie prowadzi działalność spedycyjną **i** ma w zespole kogoś, kto zna te procedury. Bez tego drugiego warunku budowa jest bezcelowa, nie tylko ryzykowna.

---

## Kamienie milowe

Liczone w miesiącach kalendarzowych od startu fazy 0, przy zespole 3–4 osób. Daty kalendarzowe ustala się dopiero po obsadzeniu zespołu.

| Kamień | Około | Wynik do pokazania |
| --- | --- | --- |
| M0 | start | obsadzony decydent zakresu, złożony wniosek o teletransmisję CEP, zamówiony eksport danych |
| M1 | miesiąc 1 | test izolacji najemców zielony w CI; logowanie i wgranie dokumentu działają |
| M2 | miesiąc 3 | kartoteka pojazdu z historią tablic i pochodzeniem pól; pierwszy import kart paliwowych |
| M3 | miesiąc 4 | migracja pełnej floty przez arkusze importu; liczby zgodne ze źródłem — **koniec fazy 1** |
| M4 | miesiąc 5–6 | DT-1 zgodny co do złotówki; lista braków blokujących pusta albo jawnie oznaczona — **koniec fazy 2**; system zastępuje dotychczasową ewidencję własnej floty |
| M5 | miesiąc 7–8 | aplikacja kierowcy: wydanie i zdanie pojazdu z licznikiem — **koniec fazy 3** |
| M6 | po M5 | środowisko demo dostępne dla pierwszych potencjalnych klientów; pierwszy audyt danych po umowie |
| M6a | po M6 | pierwszy klient zewnętrzny na produkcji: osobna spółka, osobne moduły, test izolacji na jego danych |
| M7 | warunkowo | Rent / Transport — po warsztatach z praktykami |

## Backlog wg priorytetu

### Musi być, żeby zastąpić dotychczasową ewidencję (fazy 0–2)

- najemcy, RLS, test izolacji, uprawnienia z jawnych nadań, MFA dla finansów;
- kartoteka pojazdu z polami rozszerzalnymi, historią tablic i pochodzeniem pól;
- tabela zdarzeń, rejestry towarzyszące, przypomnienia wg daty i przebiegu;
- importy: arkusze migracji, karty paliwowe, faktury kosztowe;
- dokumenty i kaskada OCR;
- silnik DT-1, stawki gminne, braki blokujące, korekty;
- dekretacja, rejestry VAT, eksport do FK, KSeF;
- raporty startowe, w tym TCO.

### Powinno być przed pierwszym klientem zewnętrznym

- platforma integracji ([platforma integracji](16-platforma-integracji.md)): API publiczne z zapisem (OAuth client credentials, zakresy, idempotencja), webhooki z podpisem HMAC, dokumentacja dla integratorów, klient API w `demo`;
- onboarding ([onboarding klienta](14-onboarding-klienta.md)): środowisko demo z przykładową flotą i szybkim testem podatkowym na liście pojazdów klienta, kreator importu z biblioteką mapowań, status najemcy `onboarding`/`active` z czyszczeniem danych importowych, raport jakości danych w PDF, zakładanie najemcy przez superadmina, pełny eksport danych przy odejściu, szablony importu;
- licencjonowanie modułów z wyłącznikiem awaryjnym;
- aplikacja kierowcy i protokoły;
- telematyka i weryfikacja tankowań;
- SSO (OIDC);
- regulamin, umowa powierzenia, polityka prywatności.

### Może być później

- Rent / CFM, Transport (warunkowe);
- opłata środowiskowa — dopiero po uzupełnieniu tabeli stawek z klasą pojazdu i źródła gęstości paliw;
- raport CO2e (osobny zestaw wskaźników);
- teletransmisja CEP jako źródło pól (po uzyskaniu dostępu).

---

## Co może wywrócić harmonogram

1. **Jakość danych źródłowych.** Na rzeczywistej flocie: 134 pojazdy z brakami blokującymi wyliczenie podatku, 623 wartości odrzucone jako niepasujące do typu pola, 1914 rozbieżności między źródłami. Uzupełnienie tego to **praca człowieka z dokumentem w ręku**, nie zadanie programistyczne — i nie zniknie przez zmianę systemu.
2. **Przepływy pracy w transporcie.** Lista modułów znana, sposób pracy — nie.
3. **KSeF.** Terminy ustawowe są zewnętrzne i nie podlegają negocjacji; zmiana API po stronie Ministerstwa może wymusić przerobienie gotowego modułu.
4. **Dostępność wiedzy dziedzinowej.** Dyspozytor, księgowa i fleet manager muszą mieć czas na warsztaty. To zwykle rzadszy zasób niż czas programisty.
5. **Decyzja o pracy offline** podjęta po rozpoczęciu fazy 3.

## Czego nie robimy w żadnej fazie

- Nie łączymy się z bazą danych cudzego systemu. Migracja wyłącznie przez arkusze importu.
- Nie budujemy kadr i płac.
- Nie utrzymujemy klienta desktopowego.
- Nie uruchamiamy przebiegu masowego na integracji, której filtr nie został potwierdzony testem kontrolnym.
- Nie dodajemy pozycji do listy znanych wyjątków w bramce testowej, żeby ją uciszyć.
