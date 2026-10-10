# Model danych i analityka

Definicje tabel: [projekt bazy danych](10-database-design.md). Ten dokument opisuje **pojęcia** i to, co z nich liczymy.

## Trzy encje nośne

### Pojazd

**Tożsamość pojazdu to VIN, nie numer rejestracyjny.**

Numer rejestracyjny zmienia się przy przerejestrowaniu, a stary dokument zostaje w dokumentacji. Scalanie po numerze dało w rzeczywistych danych **26 pojazdów pod więcej niż jedną tablicą — 53 wiersze zamiast 26** i zawyżyło sumę podatku o kilkanaście tysięcy złotych.

VIN jest przypisany do nadwozia na stałe i jako jedyna cecha przeżywa zmianę tablicy. Numer rejestracyjny to **atrybut z historią**.

> **Odwrotna pułapka, z tej samej analizy.** Wykrycie duplikatu w arkuszu **nie znaczy**, że firma płaci dwa razy. Dokumentacja opisuje dokumenty, nie flotę — każdy stary dowód rejestracyjny tworzy dodatkowy wiersz przy scalaniu.
>
> Wniosek „sześć pojazdów płaci podwójnie" okazał się artefaktem scalania: w bazie produkcyjnej każdy z tych VIN-ów występuje dokładnie raz. Zanim ogłosi się wniosek o pieniądzach, sprawdza się w systemie, który te pieniądze nalicza.

### Zdarzenie

Wspólna oś czasu pojazdu i pracownika. Typy: tankowanie, przegląd, naprawa, szkoda, mandat, rata, polisa, odczyt licznika, wydanie, zdanie, kurs, przydział, opłata drogowa.

Każde ma: najemcę, typ, datę, podmiot (pojazd lub pracownika), kwotę (opcjonalnie), dokument źródłowy, źródło pochodzenia, identyfikator u źródła i ślad audytowy.

### Dokument

Faktura, polisa, protokół, dowód rejestracyjny, zlecenie, CMR. Plik w magazynie obiektowym + metadane + wynik OCR + **kto i kiedy zatwierdził odczyt**.

---

## Pochodzenie danych — pole wie, skąd przyszło

Każde pole podatkowe pojazdu ma zapisane źródło i rangę. To nie jest metadana dla porządku — to **mechanizm rozstrzygania konfliktów**.

Ranga ustalona empirycznie, na podstawie tego, które źródło myliło się rzadziej:

| Ranga | Źródło | Uwaga |
| --- | --- | --- |
| 5 | ręczna korekta przez człowieka | człowiek poprawił, mając dokument przed sobą |
| 4 | dowód rejestracyjny (OCR) | dane urzędowe, ale odczyt bywa przekłamany |
| 3 | ERP firmy — u nas **ZSI** | ma normę EURO, której nie ma na dowodzie; nieznane DMC zapisuje jako `0` |
| 2 | platforma flotowa / telematyka — u nas **MyCar** | karta paliwowa, polisa, GPS, e-TOLL, leasing |
| 1 | import od dostawcy kart — u nas **ORLEN Flota** | ważność, status, blokady kart |
| — | CEP (teletransmisja) | ranga do ustalenia po uzyskaniu dostępu; urzędowe źródło, prawdopodobnie 4 lub wyżej |

Ranga jest **konfiguracją per najemca**, nie stałą w kodzie: u innego klienta ERP może być rzetelniejszy od OCR albo w ogóle go nie być. Tabela wyżej to ustawienie startowe, zmierzone na naszej flocie.

Rozstrzyganie: wygrywa najwyższa ranga; przy remisie — najnowszy zapis; **przy sprzeczności między źródłami tej samej rangi pole zostaje puste**, a wpis trafia na listę do rozstrzygnięcia przez człowieka.

> **„Dowód rejestracyjny ma pierwszeństwo" jest prawdziwe prawnie i zawodne technicznie.** Nasze dane z dowodu to OCR skanu. Zmierzone przypadki:
>
> - marka „LONDAIS" (śmieć) przy DMC 2080, podczas gdy zestawienie podaje Iveco ML75E16 o DMC 7500 — samo oznaczenie modelu znaczy 7,5 t;
> - Mercedes Atego z kategorią **M1** (samochód osobowy);
> - model „SPRZEDANY" — to status rekordu, nie model pojazdu.
>
> Stąd osobna lista **rekordów wewnętrznie sprzecznych**, wykrywanych bez porównania ze źródłem zewnętrznym: kategoria M1 przy modelu ciężarowym lub DMC powyżej 3,5 t, model będący statusem, marka bez samogłoski, numer homologacji krótszy niż 4 znaki.

## Zero to brak danych, nie wartość

Źródła zewnętrzne zapisują nieznane DMC jako `0`. Traktowanie zera jako wartości dało **28 z 43 fałszywych „konfliktów podatkowych"** — prawdziwy sygnał (5 przypadków) ginął w szumie.

Import zamienia zero na `NULL` dla pól, gdzie zero nie jest sensowną wartością. Ograniczenie `CHECK` w bazie tego pilnuje.

Tam, gdzie zero **jest** sensowne, fallback w kodzie używa operatora obsługującego wyłącznie `NULL` (`??`), nie operatora logicznego (`||`) — inaczej zero zostanie podmienione na wartość zapasową.

---

## Cicha zaniżona stawka — najdroższy błąd w tej dziedzinie

Nie wygląda na błąd i dlatego zasługuje na osobny rozdział.

**Od 12 t stawka podatku zależy od liczby osi i rodzaju zawieszenia.** Przy braku liczby osi silnik przyjmuje wartość domyślną — czyli **najniższą stawkę w przedziale**. Deklaracja wychodzi kompletna i wiarygodna.

Zmierzone na próbce 24 pojazdów wspólnych z bazą produkcyjną: 19 kwot identycznych, 5 różnych — wszystkie pięć z tego jednego powodu:

    WA2609J   baza 4296 zł   wyliczenie 2184 zł   (0 osi w danych, 4 w bazie)
    WA4789F   baza 2880 zł   wyliczenie 2184 zł   (2 osie w danych, 4 w bazie)
    WZ464FY   baza 2760 zł   wyliczenie 2184 zł   (2 osie w danych, 3 w bazie)

**Wymaganie dla modelu danych: pola `axles_count` i `suspension_type` dla pojazdu od 12 t nie mogą mieć wartości domyślnej.** Brak danych ma dawać status „nie da się ustalić", nie cichy fallback.

## „Ile pól jest pustych" to złe pytanie

Silnik podatkowy czyta liczbę osi i rodzaj zawieszenia **wyłącznie dla pojazdów od 12 t**. Poniżej progu kategorię wyznacza sama DMC i rodzaj; pojazdy specjalne są zwolnione niezależnie od wszystkiego.

Liczymy więc dwie różne rzeczy:

- **braki formalne** — ile pól kartoteki jest pustych;
- **braki blokujące** — ile pól, które silnik **przy tym konkretnym tonażu** faktycznie przeczyta, uniemożliwia wyliczenie.

Tylko druga liczba przekłada się na pieniądze. Na rzeczywistej flocie: 134 pojazdy z brakami blokującymi, z czego 117 bez DMC (kategorii nie da się ustalić wcale) i 17 powyżej 12 t z brakiem osi lub zawieszenia.

Kolumna `blocking_fields` w pozycji deklaracji zawiera **tylko pola, które silnik przy danym tonażu przeczyta**.

## Dane wpisane hurtem udają dane

Osobny przypadek, wart zapamiętania jako klasa problemu.

W bazie produkcyjnej **wszystkie 217 pojazdów ma `rodzaj_zawieszenia = 'pneumatyczne'`** — łącznie z motocyklem, osobówką i przyczepą z myjką ciśnieniową. To wartość wpisana hurtem przy migracji, nie pomiar. OCR wyciągnął to pole **0 razy z 945 dowodów**, bo polski dowód rejestracyjny **nie ma na nie rubryki**.

Wniosek dla projektu: pole wypełnione w 100% rekordów tą samą wartością jest **podejrzane, nie kompletne**. Raport kompletności danych powinien to wykrywać.

---

## TCO — koszt całkowity pojazdu

Podstawowa liczba, której nie daje żaden system odniesienia, bo każdy zna tylko swój wycinek.

    TCO(pojazd, okres) =
        amortyzacja albo raty leasingu
      + paliwo
      + serwis i naprawy
      + opony
      + ubezpieczenie
      + podatek od środków transportowych
      + opłaty drogowe
      + udziały własne w szkodach
      - odzyskany VAT
      - przychody z najmu (jeśli pojazd był wynajmowany)

Liczone z jednej tabeli zdarzeń, w widoku materializowanym odświeżanym nocą.

**Rozbicie na MPK i oddział wynika z przypisania pojazdu w okresie, nie z bieżącego przypisania.** Inaczej przeniesienie pojazdu między oddziałami zmienia historię.

## Wskaźniki

| Wskaźnik | Definicja | Po co |
| --- | --- | --- |
| Koszt na kilometr | TCO / przebieg w okresie | porównanie pojazdów i dostawców |
| Zużycie paliwa | litry / 100 km z tankowań i liczników | wykrycie awarii i nadużyć |
| Dostępność | dni sprawne / dni w okresie | planowanie |
| Wiek floty | średnia ważona wartością | decyzje o wymianie |
| Szkodowość | szkody na pojazd i na kierowcę | negocjacje polis |
| Emisja CO2 | litry × wskaźnik dla paliwa | ESG, raportowanie |
| Kompletność danych podatkowych | pojazdy z kompletem pól **blokujących** / wszystkie | wskaźnik ryzyka, nie porządku |

---

## Wskaźniki emisji CO2 — jedna tablica, po stronie serwera

Kilogramy liczy backend i **zwraca użyty wskaźnik** w odpowiedzi; front go tylko wyświetla.

> **Powód:** w systemie produkcyjnym istniały dwie kopie tablicy wskaźników i obie rozjechały się nie tylko ze sobą, ale i z danymi. Dopasowanie po **równości** nie trafiało w wartości zapisywane przez formularz:
>
> - benzyna liczona wskaźnikiem oleju napędowego (+8%),
> - CNG (+23%),
> - **pojazd elektryczny liczony jak spalinowy** (wskaźnik 2,5 zamiast 0).

**Dopasowanie paliwa po fragmencie, nie po równości** — importy i OCR dokładają warianty („benzyna", „elektryczny", „ON", „hybryda", „PB95").

Szczegół, który wyłapał dopiero test: polskie „elektr" i angielskie „electr" różnią się literą. Obsłużyć oba.

### Wskaźnik dla oleju napędowego: 2,65 kg CO2/l

Wartość potwierdzona rachunkiem stechiometrycznym: `0,835 kg/l × 0,862 C × 44/12 = 2,639`.

> **Spotykana wartość 2,68 to inna wielkość, nie inna wartość tej samej.** Pochodzi ze współczynników CO2**e** (uwzględniających metan i podtlenek azotu) i zwykle zakłada domieszkę biokomponentu. Sprawozdanie w CO2e wymaga **osobnego zestawu wskaźników z własnym oznaczeniem źródła**, nie podmiany tych liczb.

---

## Raporty

Definicja raportu żyje w bazie, przypisana do użytkownika i najemcy — nie w pliku na stacji roboczej. Dzięki temu „u mnie ta kolumna jest, u ciebie nie ma" przestaje być możliwe.

Mechanizm: mapa nazwa logiczna → wyrażenie SQL, używana jednocześnie w `SELECT`, filtrze i sortowaniu.

> **Bramka obowiązkowa:** każda kolumna raportu musi być albo istniejącą kolumną tabeli, albo mieć wpis w mapie wyrażeń, a samo wyrażenie może odwoływać się wyłącznie do realnych kolumn.
>
> Bez tej bramki raport ze źle nazwaną kolumną zwraca **pustą tabelę bez błędu** — to ta sama klasa problemu co ciche zera. W systemie odniesienia dotyczyło to 4 z 5 źródeł danych kreatora raportów; użytkownik widział pusty wynik i nie miał jak odróżnić „brak danych" od „zepsuta definicja".

## Czego nie budujemy

**Hurtowni danych ani osobnej warstwy BI.** Przy tej skali widoki materializowane w PostgreSQL wystarczą, a osobna hurtownia wprowadziłaby drugie miejsce, w którym liczby mogą się rozjechać z pierwszym — ta sama pułapka co dwie tablice CO2, tylko piętro wyżej.
